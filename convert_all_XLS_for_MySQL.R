# parent script for converting all tables in PRIMAGRAFTS

# find PRoXe directory
who <- system("whoami",intern=TRUE)
if(who %in% c("scott","spk22","mym97")){
	proxDir <- file.path("~","Dropbox","PRoXe")
} else if (who == "Mark"){
	proxDir <- file.path("C:","Users","Mark","Dropbox (Partners Healthcare)","PRoXe")
} else {
	stop(paste("User",who,"not recognized."))
}

# set directories
baseDir = file.path(proxDir,"db_transition")
setwd(baseDir)
dataDir = file.path(proxDir,"data_outside_app")

# read in conversion metadata
library(readxl)
# convert <- read_excel("mark_mysql/conversion_guide.xlsx") #TODO: delete if not used. 

# Toggle whether foreign key check failures cause error
FK_CHECK_FAIL=FALSE

# set MySQL login credentials
source(file.path(baseDir,"convert_all_XLS","login_credentials.R"))

########### -- Delete tables from database -- #############
library(RMySQL)
mydb <- dbConnect(RMySQL::MySQL(), user=sql_user,password = sql_password,dbname = sql_dbname,host="127.0.0.1")
dbTables <- dbListTables(mydb)
if(!FK_CHECK_FAIL) dbGetQuery(mydb,"SET foreign_key_checks = 0;")
for(t in dbTables){ 
  dbRemoveTable(mydb,t)
}
dbGetQuery(mydb,"SET foreign_key_checks = 1;")
dbDisconnect(mydb)


########### -- Create each MySQL table in a separate script -- ###########
# convert primagrafts, ... in this folder to MySQL objects.

read_in <- c("create_admin.R","create_clinical.R","create_tumor.R",
	"create_inventory.R","create_pdx.R","create_qc.R","create_pdx_seq.R",
	"create_pdx_dna_variants.R")
for(f in read_in){
	cat(paste0("\n--- Running: ",f," ---\n"))
	source(file.path(baseDir,"convert_all_XLS",f))
}

# Notes re: create_pdx_seq.R:
	# TODO. Comes from sequencing_tracking and a little from prima. 
	# Needs to be cleaned still (as of 3/6/17). -- waiting.
	# TODO: check if this is still a need.

# TODO: after the second or third of these tables, generalize some actions into functions, depend on common variables, etc.
  # For instance, perhaps read in all precursor tables in one script before starting.

### CRITICAL TODO: SCRIPT SIMILARLY FOR FOREIGN KEY CONSTRAINTS ONLY AT END OF ALL TABLE READ-IN. ###
# also consider adding checks and autoincrements
script = 'foreign_keys.R'
cat(paste0("\n--- Running: ",script," ---\n"))
source(file.path(baseDir,"convert_all_XLS",script))


### Answered: Determine where my MySQL database is stored and if easy to send to Mark.
# stored in SPKs MBP:/usr/local/var/mysql/proxe_test as .frm and .ibd files
# not simple to send, but shouldn't be too difficult:
  # try 'mysqldump' to copy: https://dev.mysql.com/doc/refman/5.7/en/copying-databases.html
  # else try https://mediatemple.net/community/products/dv/204403864/export-and-import-mysql-databases
  # else try http://stackoverflow.com/questions/22447651/copying-mysql-databases-from-one-computer-to-another