ASO_lifecycle deployment for slc6
=============
./install.sh #will deploy the ASO on $HOME/

cd $HOME/103pre4_lifecycle/current

./config/asyncstageout/manage activate-asyncstageout

./config/asyncstageout/manage start-services

./config/asyncstageout/manage init-asyncstageout

./config/asyncstageout/manage start-asyncstageout

Config Files
--------------
