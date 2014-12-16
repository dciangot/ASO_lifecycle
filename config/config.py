from WMCore.Configuration import Configuration
config = Configuration()
config.section_('General')
config.General.workDir = '/data/ASO/async_install_103pre3/v01/install/asyncstageout'
config.section_('CoreDatabase')
config.CoreDatabase.connectUrl = 'http://couch_db_user:couch_db_password@crabas2.lnl.infn.it:5996/asynctransfer_agent'
config.section_('Agent')
config.Agent.hostName = 'crabas2.lnl.infn.it'
config.Agent.contact = 'Your mail address'
config.Agent.teamName = 'Your team name'
config.Agent.agentName = 'Agent name'
config.component_('AsyncTransfer')
config.AsyncTransfer.config_couch_instance = 'http://couch_db_user:couch_db_password@crabas2.lnl.infn.it:5996'
config.AsyncTransfer.user_monitoring_db = 'user_monitoring_asynctransfer'
config.AsyncTransfer.db_source = 'analysis_wmstats'
config.AsyncTransfer.expiration_days = 30
config.AsyncTransfer.pool_size = 80
config.AsyncTransfer.pollInterval = 10
config.AsyncTransfer.jobs_database = 'jobs'
config.AsyncTransfer.max_retry = 3
config.AsyncTransfer.log_level = 20
config.AsyncTransfer.componentDir = '/data/ASO/async_install_103pre3/v01/install/asyncstageout/AsyncTransfer'
config.AsyncTransfer.requests_database = 'request_database'
config.AsyncTransfer.namespace = 'AsyncStageOut.AsyncTransfer'
config.AsyncTransfer.config_database = 'asynctransfer_config'
config.AsyncTransfer.serverDN = '/C=IT/O=INFN/OU=Host/L=Perugia/CN=crab.pg.infn.it'
config.AsyncTransfer.cache_area = 'https://cmsweb-testbed.cern.ch/crabserver/preprod/filemetadata'
config.AsyncTransfer.pollViewsInterval = 10
config.AsyncTransfer.algoName = 'FIFOPriority'
config.AsyncTransfer.serviceCert = '/path/to/valid/host-cert'
config.AsyncTransfer.transfer_script = 'ftscp'
config.AsyncTransfer.schedAlgoDir = 'AsyncStageOut.SchedPlugins'
config.AsyncTransfer.couch_user_monitoring_instance = 'http://couch_db_user:couch_db_password@crabas2.lnl.infn.it:5996'
config.AsyncTransfer.serviceKey = '/path/to/valid/host-key'
config.AsyncTransfer.cleanEnvironment = True
config.AsyncTransfer.data_source = 'http://couch_db_user:couch_db_password@crabas2.lnl.infn.it:5996'
config.AsyncTransfer.credentialDir = '/tmp/credentials/'
config.AsyncTransfer.max_files_per_transfer = 100
config.AsyncTransfer.pluginDir = 'AsyncStageOut.Plugins'
config.AsyncTransfer.files_database = 'asynctransfer'
config.AsyncTransfer.pluginName = 'CentralMonitoring'
config.AsyncTransfer.UISetupScript = '/afs/cern.ch/cms/LCG/LCG-2/UI/cms_ui_env.sh'
config.AsyncTransfer.summaries_expiration_days = 30
config.AsyncTransfer.opsProxy = '/data/proxy'
config.AsyncTransfer.couch_instance = 'http://couch_db_user:couch_db_password@crabas2.lnl.infn.it:5996'
config.component_('Reporter')
config.Reporter.namespace = 'AsyncStageOut.Reporter'
config.Reporter.componentDir = '/data/ASO/async_install_103pre3/v01/install/asyncstageout/Reporter'
config.component_('DBSPublisher')
config.DBSPublisher.config_couch_instance = 'http://couch_db_user:couch_db_password@crabas2.lnl.infn.it:5996'
config.DBSPublisher.publication_pool_size = 80
config.DBSPublisher.publication_max_retry = 3
config.DBSPublisher.pollInterval = 600
config.DBSPublisher.log_level = 20
config.DBSPublisher.componentDir = '/data/ASO/async_install_103pre3/v01/install/asyncstageout/DBSPublisher'
config.DBSPublisher.namespace = 'AsyncStageOut.DBSPublisher'
config.DBSPublisher.config_database = 'asynctransfer_config'
config.DBSPublisher.block_closure_timeout = 18800
config.DBSPublisher.serverDN = '/C=IT/O=INFN/OU=Host/L=Perugia/CN=crab.pg.infn.it'
config.DBSPublisher.cache_area = 'https://cmsweb-testbed.cern.ch/crabserver/preprod/filemetadata'
config.DBSPublisher.algoName = 'FIFOPriority'
config.DBSPublisher.workflow_expiration_time = 3
config.DBSPublisher.serviceCert = '/path/to/valid/host-cert'
config.DBSPublisher.schedAlgoDir = 'AsyncStageOut.SchedPlugins'
config.DBSPublisher.serviceKey = '/path/to/valid/host-key'
config.DBSPublisher.publish_dbs_url = 'https://cmsweb.cern.ch/dbs/prod/phys03/DBSWriter'
config.DBSPublisher.credentialDir = '/tmp/credentials/'
config.DBSPublisher.files_database = 'asynctransfer'
config.DBSPublisher.UISetupScript = '/afs/cern.ch/cms/LCG/LCG-2/UI/cms_ui_env.sh'
config.DBSPublisher.max_files_per_block = 100
config.DBSPublisher.opsProxy = '/data/proxy'
config.DBSPublisher.couch_instance = 'http://couch_db_user:couch_db_password@crabas2.lnl.infn.it:5996'
config.component_('FilesCleaner')
config.FilesCleaner.log_level = 20
config.FilesCleaner.componentDir = '/data/ASO/async_install_103pre3/v01/install/asyncstageout/FilesCleaner'
config.FilesCleaner.config_couch_instance = 'http://couch_db_user:couch_db_password@crabas2.lnl.infn.it:5996'
config.FilesCleaner.namespace = 'AsyncStageOut.FilesCleaner'
config.FilesCleaner.config_database = 'asynctransfer_config'
config.FilesCleaner.files_database = 'asynctransfer'
config.FilesCleaner.UISetupScript = '/afs/cern.ch/cms/LCG/LCG-2/UI/cms_ui_env.sh'
config.FilesCleaner.filesCleaningPollingInterval = 14400
config.FilesCleaner.opsProxy = '/data/proxy'
config.FilesCleaner.couch_instance = 'http://couch_db_user:couch_db_password@crabas2.lnl.infn.it:5996'
config.component_('Statistics')
config.Statistics.couch_statinstance = 'http://couch_db_user:couch_db_password@crabas2.lnl.infn.it:5996'
config.Statistics.statitics_database = 'asynctransfer_stat'
config.Statistics.log_level = 20
config.Statistics.componentDir = '/data/ASO/async_install_103pre3/v01/install/asyncstageout/Statistics'
config.Statistics.config_couch_instance = 'http://couch_db_user:couch_db_password@crabas2.lnl.infn.it:5996'
config.Statistics.namespace = 'AsyncStageOut.Statistics'
config.Statistics.config_database = 'asynctransfer_config'
config.Statistics.files_database = 'asynctransfer'
config.Statistics.expiration_days = 7
config.Statistics.pollStatInterval = 1800
config.Statistics.opsProxy = '/path/to/ops/proxy'
config.Statistics.mon_database = 'asynctransfer'
config.Statistics.couch_instance = 'http://couch_db_user:couch_db_password@crabas2.lnl.infn.it:5996'
config.component_('RetryManager')
config.RetryManager.algoName = 'DefaultRetryAlgo'
config.RetryManager.log_level = 10
config.RetryManager.componentDir = '/data/ASO/async_install_103pre3/v01/install/asyncstageout/RetryManager'
config.RetryManager.opsProxy = '/data/proxy'
config.RetryManager.namespace = 'AsyncStageOut.RetryManager'
config.RetryManager.cooloffTime = 7200
config.RetryManager.retryAlgoDir = 'AsyncStageOut.RetryPlugins'
config.RetryManager.files_database = 'asynctransfer'
config.RetryManager.pollInterval = 300
config.RetryManager.couch_instance = 'http://couch_db_user:couch_db_password@crabas2.lnl.infn.it:5996'
