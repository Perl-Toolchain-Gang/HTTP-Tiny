#!perl

use strict;
use warnings;

use Test::More 0.88;

plan skip_all => "IO::Socket::SSL required for SSL tests"
  unless eval { require IO::Socket::SSL; 1 };

plan skip_all => "Net::SSLeay required for SSL tests"
  unless eval { require Net::SSLeay; 1 };

use HTTP::Tiny;

# Test that a user-provided SSL_create_ctx_callback in SSL_options is not
# silently overwritten but instead composed with the internal MODE_AUTO_RETRY
# callback. See https://github.com/Perl-Toolchain-Gang/HTTP-Tiny/issues/19

# Test 1: _ssl_args preserves the user's SSL_create_ctx_callback
{
    my $user_cb = sub { 'user' };

    my $h = bless {
        SSL_options => { SSL_create_ctx_callback => $user_cb },
        verify_SSL  => 0,
    }, 'HTTP::Tiny::Handle';

    my $ssl_args = $h->_ssl_args('example.com');

    is( ref($ssl_args->{SSL_create_ctx_callback}), 'CODE',
        '_ssl_args preserves SSL_create_ctx_callback as CODE ref' );

    is( $ssl_args->{SSL_create_ctx_callback}, $user_cb,
        '_ssl_args preserves the exact user callback reference' );
}

# Test 2: start_ssl composes the user callback with the internal MODE_AUTO_RETRY callback
{
    my $mode_auto_retry_called = 0;
    my $user_cb_called         = 0;
    my $user_cb = sub { $user_cb_called++ };

    no warnings 'redefine';
    local *Net::SSLeay::CTX_set_mode  = sub { $mode_auto_retry_called++ };
    local *Net::SSLeay::MODE_AUTO_RETRY = sub { 0 };

    my @captured_args;
    local *IO::Socket::SSL::start_SSL = sub {
        my ($class, $fh, @args) = @_;
        @captured_args = @args;
        bless $fh, 'IO::Socket::SSL'; # simulate in-place SSL upgrade
    };

    my $fh = bless( {}, 'IO::Socket::INET' );
    my $h = bless {
        fh => $fh,
        SSL_options => { SSL_create_ctx_callback => $user_cb },
        verify_SSL  => 0,
    }, 'HTTP::Tiny::Handle';

    $h->start_ssl('example.com');

    my %args = @captured_args;

    ok( exists $args{SSL_create_ctx_callback},
        'start_ssl passes SSL_create_ctx_callback to IO::Socket::SSL' );
    is( ref($args{SSL_create_ctx_callback}), 'CODE',
        'SSL_create_ctx_callback passed to IO::Socket::SSL is a CODE ref' );

    # Invoke the callback and verify both internal and user callbacks ran
    $args{SSL_create_ctx_callback}->(my $ctx = {});

    ok( $mode_auto_retry_called,
        'internal CTX_set_mode/MODE_AUTO_RETRY is called from composed callback' );
    ok( $user_cb_called,
        'user SSL_create_ctx_callback is also called from composed callback' );
}

# Test 3: without a user callback, the internal MODE_AUTO_RETRY callback still fires
{
    my $mode_auto_retry_called = 0;

    no warnings 'redefine';
    local *Net::SSLeay::CTX_set_mode    = sub { $mode_auto_retry_called++ };
    local *Net::SSLeay::MODE_AUTO_RETRY = sub { 0 };

    my @captured_args;
    local *IO::Socket::SSL::start_SSL = sub {
        my ($class, $fh, @args) = @_;
        @captured_args = @args;
        bless $fh, 'IO::Socket::SSL';
    };

    my $fh = bless( {}, 'IO::Socket::INET' );
    my $h = bless {
        fh => $fh,
        SSL_options => {},
        verify_SSL  => 0,
    }, 'HTTP::Tiny::Handle';

    $h->start_ssl('example.com');

    my %args = @captured_args;
    $args{SSL_create_ctx_callback}->(my $ctx = {});

    ok( $mode_auto_retry_called,
        'internal MODE_AUTO_RETRY still fires when no user callback provided' );
}

done_testing;
