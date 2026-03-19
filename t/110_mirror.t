#!perl

use strict;
use warnings;

use File::Basename;
use Test::More 0.88;
use lib 't';
use Util qw[tmpfile rewind slurp monkey_patch dir_list parse_case
  clear_socket_source set_socket_source sort_headers $CRLF $LF];
use HTTP::Tiny;
use File::Temp qw/tempdir/;
use File::Spec;

BEGIN { monkey_patch() }

my $tempdir = tempdir( TMPDIR => 1, CLEANUP => 1 );
my $tempfile = File::Spec->catfile( $tempdir, "tempfile.txt" );

my $known_epoch = 760233600;
my $day = 24*3600;

my %timestamp = (
  'modified.txt'      => $known_epoch - 2 * $day,
  'not-modified.txt'  => $known_epoch - 2 * $day,
  'partial.txt'       => $known_epoch - 2 * $day,
);

for my $file ( dir_list("corpus", qr/^mirror/ ) ) {
  1 while unlink $tempfile;
  my $data = do { local (@ARGV,$/) = $file; <> };
  my ($params, $expect_req, $give_res) = split /--+\n/, $data;
  # cleanup source data
  my $version = HTTP::Tiny->VERSION || 0;
  $expect_req =~ s{VERSION}{$version};
  s{\n}{$CRLF}g for ($expect_req, $give_res);

  # figure out what request to make
  my $case = parse_case($params);
  my $url = $case->{url}->[0];
  my %options;

  my %headers;
  for my $line ( @{ $case->{headers} } ) {
    my ($k,$v) = ($line =~ m{^([^:]+): (.*)$}g);
    $headers{$k} = $v;
  }
  $options{headers} = \%headers if %headers;
  $options{continue} = 1 if exists $case->{continue};

  # maybe create a file
  (my $url_basename = $url) =~ s{.*/}{};
  my $initial_size = 0;
  if ( exists $case->{continue} && $case->{initial_content} ) {
    my $content = join('', @{ $case->{initial_content} });
    $initial_size = length($content);
    open my $fh, ">", $tempfile;
    binmode $fh;
    print $fh $content;
    close $fh;
    if ( my $mtime = $timestamp{$url_basename} ) {
      utime $mtime, $mtime, $tempfile;
      if ($^O eq 'MSWin32') {
        $timestamp{$url_basename} = (stat $tempfile)[9];
      }
    }
  }
  elsif ( my $mtime = $timestamp{$url_basename} ) {
    open my $fh, ">", $tempfile;
    close $fh;
    utime $mtime, $mtime, $tempfile;
    if ($^O eq 'MSWin32') {
        # Deal with stat and daylight savings issues on Windows
        # by reading back mtime
        $timestamp{$url_basename} = (stat $tempfile)[9];
    }
  }

  # setup mocking and test
  my $res_fh = tmpfile($give_res);
  my $req_fh = tmpfile();

  my $http = HTTP::Tiny->new( keep_alive => 0 );
  clear_socket_source();
  set_socket_source($req_fh, $res_fh);

  my @call_args = %options ? ($url, $tempfile, \%options) : ($url, $tempfile);
  my $response  = $http->mirror(@call_args);

  my $got_req = slurp($req_fh);

  my $label = basename($file);

  is( sort_headers($got_req), sort_headers($expect_req), "$label request" );

  my ($rc) = $give_res =~ m{\S+\s+(\d+)}g;
  is( $response->{status}, $rc, "$label response code $rc" )
    or diag $response->{content};

  if ( substr($rc,0,1) eq '2' ) {
    ok( $response->{success}, "$label success flag true" );
    ok( -e $tempfile, "$label file created" );
    if ( $rc eq '206' ) {
      ok( -s $tempfile > $initial_size, "$label file grew after resume" );
    }
  }
  elsif ( $rc eq '304' ) {
    ok( $response->{success}, "$label success flag true" );
    is( (stat($tempfile))[9], $timestamp{$url_basename},
      "$label file not overwritten" );
  }
  else {
    ok( ! $response->{success}, "$label success flag false" );
    ok( ! -e $tempfile, "$label file not created" );
  }
}

# Explicit test: continue option with 412 fallback to 304
{
  1 while unlink $tempfile;

  my $content  = 'abcdefg';
  my $mtime412 = $known_epoch - 2 * $day;
  open my $fh, '>', $tempfile; binmode $fh; print $fh $content; close $fh;
  utime $mtime412, $mtime412, $tempfile;
  if ($^O eq 'MSWin32') { $mtime412 = (stat $tempfile)[9] }

  my $version = HTTP::Tiny->VERSION || 0;

  my $res1 = tmpfile("HTTP/1.1 412 Precondition Failed${CRLF}Content-Length: 0${CRLF}${CRLF}");
  my $req1 = tmpfile();
  my $res2 = tmpfile("HTTP/1.1 304 Not Modified${CRLF}${CRLF}");
  my $req2 = tmpfile();

  my $http = HTTP::Tiny->new( keep_alive => 0 );
  clear_socket_source();
  set_socket_source($req1, $res1);
  set_socket_source($req2, $res2);

  my $response = $http->mirror(
    'http://example.com/partial.txt', $tempfile, { continue => 1 }
  );

  my $req1_text = slurp($req1);
  my $req2_text = slurp($req2);

  ok( $req1_text =~ /Range:\s*bytes=7-/i,     'continue 412 fallback: first request has Range header' );
  ok( $req1_text =~ /If-Range:/i,              'continue 412 fallback: first request has If-Range header' );
  ok( $req2_text =~ /If-Modified-Since:/i,     'continue 412 fallback: second request has If-Modified-Since' );
  ok( !($req2_text =~ /Range:/i),              'continue 412 fallback: second request has no Range header' );
  is( $response->{status}, '304',              'continue 412 fallback: final status 304' );
  ok( $response->{success},                    'continue 412 fallback: success true' );
  ok( -e $tempfile,                            'continue 412 fallback: file still exists' );
  is( -s $tempfile, length($content),          'continue 412 fallback: file size unchanged' );
}

done_testing;
