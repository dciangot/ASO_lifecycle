echo $*
export T0FeedBasedir='/afs/cern.ch/user/r/rehn/public/PHEDEX/Testbed/T0FeedTest'
export T0FeedDropDir='/data/DevNodes/state/inject-tmdb/inbox'
#export T0FeedDropDir='/tmp/testdrop'

export PERL5LIB=${PERL5LIB}:${T0FeedBasedir}/Perl_libs
export PATH=/usr/bin:${PATH}
