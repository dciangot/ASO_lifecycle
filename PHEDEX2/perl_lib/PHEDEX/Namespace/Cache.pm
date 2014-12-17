package PHEDEX::Namespace::Cache;
# Implement caching of results in the namespace framework.
# It just records all results in a hash, and never expires them.
use strict;
use warnings;
use PHEDEX::Core::Util ( qw / deep_copy / );

sub new
{
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $h = shift;

# Params and options are module-specific
  my %params = (
		 VERBOSE => $h->{VERBOSE} || 0,
		 DEBUG	 => $h->{DEBUG}   || 0,
		 cache	 => $h->{AGENT}->{AGENT_CACHE_NAMESPACE} || {},
		 stats	 => {},
              );
  my $self = \%params;
  bless($self, $class);
  return $self;
}

sub store
{
  my ($self,$attr,$args,$result) = @_;
# $attr is the method that was requested. 'size', 'checksum_type' etc...
# $args is the file (or files) that the attribute was requested for

# $flatargs takes account of the case where $args is an array. In practise
# this is unlikely to happen, I'm not even sure if it makes sense if it does
  my $flatargs;
  if ( ref($args) eq 'ARRAY' ) { $flatargs = join(' ',@{$args}); }
  else { $flatargs = $args };

# use 'deep_copy' from the Util package to make sure we have immutable results
  return $self->{cache}{$flatargs}{$attr} = deep_copy($result);
}

sub fetch
{
  my ($self,$attr,$args) = @_;
  my $flatargs;
  if ( ref($args) eq 'ARRAY' ) { $flatargs = join(' ',@{$args}); }
  else { $flatargs = $args };
  if ( exists($self->{cache}{$flatargs}) &&
       exists($self->{cache}{$flatargs}{$attr}) )
  {
    $self->{stats}{hit}++;
    return deep_copy($self->{cache}{$flatargs}{$attr});
  }
  $self->{stats}{miss}++;
  return undef;
}

sub DESTROY
{
  my $self = shift;
  return unless $self->{VERBOSE};
  my ($hit,$calls,$pct,$entries);
  $hit   = $self->{stats}{hit} || 0;
  $calls = ($self->{stats}{miss} || 0) + $hit;
  $pct   = ( $calls ? int(100*$hit/($calls)) : 0 );
  $entries = scalar keys %{$self->{cache}};
  print "Cache statistics: $hit hits, $calls calls ($pct%), $entries entries\n";
}

1;
