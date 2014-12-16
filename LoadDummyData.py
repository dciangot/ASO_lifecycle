"""
Insert dummy data into the AsyncTransfer CouchDB instance
"""
from AsyncStageOut import getHashLfn
import random
from WMCore.Database.CMSCouch import CouchServer
from WMCore.Configuration import loadConfigurationFile
import datetime
import time

config = loadConfigurationFile('config/asyncstageout/config.py')
server = CouchServer(config.AsyncTransfer.couch_instance)
db = server.connectDatabase(config.AsyncTransfer.files_database)

users = ['dciangot', 'riahi', 'tizio', 'caio']

sites = ['T2_AT_Vienna',# 'T2_BE_IIHE', 'T2_BE_UCL',
         'T2_CH_CSCS', 'T2_CN_Beijing',
         'T2_EE_Estonia', 'T2_ES_CIEMAT', 'T2_ES_IFCA',
         'T2_FI_HIP', 'T2_FR_GRIF_IRFU',
         'T2_IT_Legnaro', 'T2_IT_Pisa','T2_IT_Rome', 'T2_IT_Bari' ,'T2_KR_KNU', 'T2_PK_NCP',
         'T2_PT_NCG_Lisbon',
         'T2_RU_INR', 'T2_RU_ITEP', 'T2_RU_JINR', 'T2_RU_PNPI',
         'T2_RU_RRC_KI', 'T2_RU_SINP', 'T2_TR_METU', 'T2_TW_Taiwan',
         'T2_UA_KIPT', 'T2_UK_London_IC',
         'T2_UK_SGrid_Bristol', 'T2_UK_SGrid_RALPP', 'T2_US_Caltech',
         'T2_US_Florida', 'T2_US_MIT', 'T2_US_Nebraska',
         'T2_US_Wisconsin']

users_dest = {'dciangot': 'T2_IT_Legnaro', 'riahi': 'T2_IT_Pisa', 'tizio': 'T2_IT_Rome', 'caio':'T2_IT_Bari'}

size = 288000 #TODO: read from script input
i = 1
j = 1
# lfn_base has store/temp in it twice to make sure that
# the temp->permananet lfn change is correct.
lfn_base = '/store/temp/user/%s/my_2cool_dataset/file-%s-%s.root'
#lfn_base = '/store/user/%s/file-%s-%s.root'

#job_end_time =datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
last_update = int(time.time());

now2 = str(datetime.datetime.now())
#id=random.randint(1000, 1999)
#userd=random.choice(users)
#user = '%s_%s' % (userd,random.randint(0,5))
#dest = users_dest[userd]

print "Script starts at %s" %now2

while i <= size:
    #time.sleep(0.05)
    userd=random.choice(users)
    user = '%s_%s' % (userd,random.randint(0,49))
    now = str(datetime.datetime.now())   
    id=random.randint(1000, 9999)
    dest = users_dest[userd]
    _id=getHashLfn(lfn_base % (user,id , i))
    state='new'
    file_doc = {'_id': '%s' %(_id) ,
                'lfn': lfn_base % (user,
                                   id,
                                   i),
                #'dn': 'UserDN',
                #'_attachments': '',
                'checksums': {
                         "adler32": "ad:b2378cab"
                },
                "failure_reason": [
                ],
                'group': '',
                'publish':1,
                'timestamp': now,
                'source':  random.choice(sites),
                'role': '',
                'type': 'output',
                'dbSource_url': 'gWMS',
                'dbs_url': 'https://cmsweb.cern.ch/dbs/prod/global/DBSReader',
                'inputdataset': 'NULL',
                'publication_state': 'not_published',
                'publication_retry_count': [
                ],
                'group': '',
                'jobid': random.randint(1,1000),
                'destination': dest,
                'start_time' : now,
                'end_time': '',
                'state' : state,
                'last_update': last_update,
                'publish_dbs_url': 'https://cmsweb.cern.ch/dbs/prod/phys03/DBSWriter',
                'workflow': 'CmsRunAnalysis-%s' %(random.randint(1,500)),
                'retry_count': [],
		'job_retry_count': [],
                'user': user,
                'size': 300000#random.randint(1, 9999),
                #'job_end_time': job_end_time
    }
    #print "uploading docs in %s and db %s" %(config.AsyncTransfer.couch_instance, config.AsyncTransfer.files_database)
    try:
        db.queue(file_doc)
    except Exception, ex:
        print "Error when queuing docs"
        print ex
    #print "doc queued %s" %file_doc
    # TODO: Bulk commit of documents
    if i%800==0:
     userd=random.choice(users)
     user = '%s_%s' % (userd,random.randint(0,5))
     try:
        db.commit()
        print "commiting docs [ %s , %s ] at %s" %( i-800 , i , str(datetime.datetime.now()))
     except Exception, ex:
        print "Error when commiting docs"
        print ex
     time.sleep(60)
    i += 1
