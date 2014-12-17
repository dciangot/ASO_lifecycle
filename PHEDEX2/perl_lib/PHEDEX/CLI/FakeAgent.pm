package PHEDEX::CLI::FakeAgent;

# TODO: set only the direct or proxy variables as required, pass proxy
# configuration to dataservice security module

use strict;
use warnings;
use base 'PHEDEX::CLI::UserAgent';
use PHEDEX::Core::Timing;
use Data::Dumper;
use Getopt::Long;
use Sys::Hostname;
use Socket;
use CGI;
use Apache2::Const -compile => qw(FORBIDDEN OK);

our $VERSION = 1.0;
our @env_keys = ( qw / PROXY DEBUG CERT_FILE KEY_FILE CA_FILE CA_DIR / );
our %env_keys = map { $_ => 1 } @env_keys;

our %params =
	(
	  URL		=> undef,
    	  CERT_FILE	=> undef,
	  KEY_FILE	=> undef,
	  CA_FILE	=> undef,
	  CA_DIR	=> undef,
	  NOCERT	=> undef,
	  PROXY		=> undef,
	  TIMEOUT	=> 30,

	  VERBOSE	=> $ENV{PHEDEX_VERBOSE} || 0,
	  DEBUG		=> $ENV{PHEDEX_DEBUG}   || 0,
	  FORMAT	=> undef,
	  INSTANCE	=> undef,
	  CALL		=> undef,
	  TARGET	=> undef,

	  PARANOID	=> 1,
	  ME	 	=> __PACKAGE__ . '/' . $VERSION,

	  SERVICE	=> undef,
#	  Hope I'm not on a node with multiple network interfaces!
	  REMOTE_ADDR	=> inet_ntoa((gethostbyname(hostname))[4]),

	  CLEAN_ENVIRONMENT	=> 1,
	);

sub new
{
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my %h = @_;

  my $self;
  $self = $class->SUPER::new();
  map { $self->{$_} = $params{$_} } keys %params;
  map { $self->{$_} = $h{$_}  if defined($h{$_}) } keys %h;
  bless $self, $class;

  $self->init();
  $self->CMSAgent($self->{ME});
  return $self;
}

sub AUTOLOAD
{
  my $self = shift;
  my $attr = our $AUTOLOAD;
  $attr =~ s/.*:://;
  if ( exists($params{$attr}) )
  {
    if ( @_ )
    {
      $self->{$attr} = shift;
      $self->init() if exists $env_keys{$attr};
    }
    return $self->{$attr};
  }

  return unless $attr =~ /[^A-Z]/;  # skip DESTROY and all-cap methods
  my $parent = "SUPER::" . $attr;
  return $self->$parent(@_);
}

sub init
{
  my $self = shift;

  $self->SUPER::init();

  $ENV{HTTPS} = $ENV{HTTP_HTTPS} = $self->{NOCERT} ? 'off' : 'on';
  foreach ( qw / REMOTE_ADDR / )
  {
    $ENV{$_} = $self->{$_} if $self->{$_};
  }
}

sub Dump { return Data::Dumper->Dump([ (shift) ],[ __PACKAGE__ ]); }

sub target
{
  my $self = shift;
  my $path_info = $self->path_info();
  $ENV{PATH_INFO} = $path_info;
  return $self->{URL} . $path_info;
}

sub post
{
  $ENV{REQUEST_METHOD} = 'POST';
  return (shift)->_action(@_);
}

sub get
{
  $ENV{REQUEST_METHOD} = 'GET';
  return (shift)->_action(@_);
}

sub _prepare_request
{
# Cribbed almost entirely from LWP::UserAgent::prepare_request and friends...
  require HTTP::Request::Common;
  my ($self, $url, $args ) = @_;
  my ($request,$new_request);

  if ( $ENV{REQUEST_METHOD} eq 'POST' )
  {
    $request = HTTP::Request::Common::POST( $url, $args );
    $self->_request_sanity_check($request);
    $new_request = $self->prepare_request($request);
    $ENV{CONTENT_LENGTH} = $request->{_headers}{'content-length'};
    $ENV{CONTENT_TYPE} = $request->{_headers}{'content-type'};
    $ENV{QUERY_STRING} = $request->{_content};

#   Fool CGI.pm into reading from our fake content instead of from a
#   filehandle or socket.
    *CGI::read_from_client = sub {
      my ($self,$query_string,$content_length,$offset) = @_;
      ${$query_string} = $request->{_content};
    };
  }
  if ( $ENV{REQUEST_METHOD} eq 'GET' )
  {
    $request = HTTP::Request::Common::GET( $url, $args );
    $ENV{QUERY_STRING} = join('&', map {"$_=$args->{$_}"} keys %{$args});
    $self->_request_sanity_check($request);
    $new_request = $self->prepare_request($request);
    $request->{_uri} .= '?' . $ENV{QUERY_STRING};
  }

  return $new_request;
}

sub _action
{
  my ($self,$url,$args) = @_;

  my ($service,$service_name,$obj,$h,$content,$r);
  if ( !$self->{NOCERT} )
  {
    $ENV{SSL_CLIENT_VERIFY} = $ENV{HTTP_SSL_CLIENT_VERIFY} = 'SUCCESS';
    defined($ENV{SSL_CLIENT_S_DN}) or
    do
    {
      open SSL, "openssl x509 -in $self->{CERT_FILE} -subject |" or
	die "SSL_CLIENT_S_DN environment variable not set and cannot read certificate to set it\n";
      my $in_cert_body = 0;
      my @cert_lines;
      $ENV{SSL_CLIENT_CERT} = "";
        while ( <SSL> )
        {
	    if (m%^subject=\s+(.*)$%) {
		$ENV{SSL_CLIENT_S_DN} = $1;
	    }
	    if (/BEGIN CERTIFICATE/) { $in_cert_body = 1; }
	    if ($in_cert_body) {
		chomp;
		push @cert_lines, $_;
	    }
	    if (/END CERTIFICATE/) { $in_cert_body = 0; }
        }
        close SSL; # Who cares about return codes...?
      $ENV{SSL_CLIENT_CERT} = join(' ', @cert_lines);
    } or die "SSL_CLIENT_S_DN environment variable not set\n";
    $ENV{HTTP_SSL_CLIENT_S_DN} = $ENV{SSL_CLIENT_S_DN};
    $ENV{HTTP_SSL_CLIENT_CERT} = $ENV{SSL_CLIENT_CERT};
  }
  
  my $stdout = '';
  eval {
      $service_name = $self->{SERVICE};
      open (local *STDOUT,'>',\$stdout); # capture STDOUT of $call
      eval("use $service_name");
      die $@ if $@;

#     Allow re-use of the FakeAgent in the same process
      CGI::_reset_globals();
      $service = $service_name->new();
      $service->{ARGS}{$_} = $args->{$_} for keys %{$args};
      print "FakeAgent _action PATH_INFO:$ENV{PATH_INFO}\n" if $self->{DEBUG};
      print "FakeAgent CONFIG:\n", Dumper($service->{CONFIG}), "\n" if $self->{DEBUG};
#      print "FakeAgent _action ARGS:\n",Dumper($service->{ARGS}), "\n" if $self->{DEBUG};
      my $request = $self->_prepare_request( $url, $args );
      $service->invoke();
      $service->{CORE}->{DBH}->disconnect() if $service->{CORE}->{DBH}; # get rid of annoying warning
  };
  if ($@) {
      print STDERR Data::Dumper->Dump( [ $self, $service ], [ __PACKAGE__, $service_name ] );
      $r = HTTP::Response->new( 500, 'Fake internal server error', HTTP::Headers->new(),
				"Internal server error: $@\nstdout:\n$stdout");
  } else {
      $h = HTTP::Headers->new();
      foreach ( split("\r\n", $stdout) )
      {
	  if (m%^([^:]*):\s+(.+)\s*$%) {
	      $h->header( "$1" => $2 );
	  } else {
	      $content .= $_;
	  }
      }
      $r = HTTP::Response->new( 200, 'Fake successfull return', $h, $content );
  }
  return $r;
}

1;
