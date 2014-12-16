#! /bin/sh

set -x
SW_AREA=/home/dboard/
#REPO="-r comp=comp"
#REPO="-r comp=comp.pre"
#REPO="-r comp=comp.pre.mcinquil"
REPO="-r comp=comp.pre.riahi"
#DIR="/home/crab/async_install_pre5"
##DIR="/data/ASO/async_install_pre15test"
#DIR="/data/ASO/async_install_101"
DIR="/home/dboard/Diego/103pre4_lifecycle"

cd $SW_AREA/Diego
#wget -O cfg.zip --no-check-certificate https://github.com/geneguvo/deployment/zipball/12.07b
#wget -O cfg.zip --no-check-certificate https://github.com/geneguvo/deployment/zipball/12.10c
###wget -O cfg.zip --no-check-certificate https://github.com/dmwm/deployment/zipball/12.10c
#
#wget -O cfg.zip --no-check-certificate https://github.com/dmwm/deployment/zipball/HG1412a
#unzip cfg.zip
#mv dmwm-deployment* cfg_aso

###mv dmwm-deployment-20cd88f cfg
#mv geneguvo-deployment-d52c4e4 cfg
##mv geneguvo-deployment-a2cf4d0 cfg
cd cfg_aso

#cd deployment-HG1401h
#./Deploy ${REPO} -R asyncstageout@1.0.1 -s prep -A slc5_amd64_gcc461 -t v01 $DIR asyncstageout asyncstageout/offsite
#./Deploy ${REPO} -R asyncstageout@1.0.1 -s sw -A slc5_amd64_gcc461 -t v01 $DIR asyncstageout asyncstageout/offsite
#./Deploy ${REPO} -R asyncstageout@1.0.1 -s post -A slc5_amd64_gcc461 -t v01 $DIR asyncstageout asyncstageout/offsite

./Deploy ${REPO} -R asyncstageout@1.0.3pre4 -s prep -A slc6_amd64_gcc481 -t v01 $DIR asyncstageout
./Deploy ${REPO} -R asyncstageout@1.0.3pre4 -s sw -A slc6_amd64_gcc481 -t v01 $DIR asyncstageout
./Deploy ${REPO} -R asyncstageout@1.0.3pre4 -s post -A slc6_amd64_gcc481 -t v01 $DIR asyncstageout

rm -fr ASO_lifecycle
git clone git@github.com:dciangot/ASO_lifecycle.git
rm -fr $SW_AREA/ASO_lifecycle
mv ASO_lifecycle $SW_AREA/ASO_lifecycle
cp $SW_AREA/ASO_lifecycle/manage $DIR/current/config/asyncstageout/
cp $SW_AREA/ASO_lifecycle/LoadDummyData.py $DIR/current/
cd $DIR/current
rm -fr $SW_AREA/ASO_lifecycle
