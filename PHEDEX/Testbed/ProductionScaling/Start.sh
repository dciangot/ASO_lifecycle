CONFIG=PHEDEX/Testbed/ProductionScaling/Config.Test
eval $(PHEDEX/Utilities/Master -config $CONFIG environ)

. $(dirname $0)/InitDB.sh

rm -fr logs state
PHEDEX/Utilities/Master -config $CONFIG start
