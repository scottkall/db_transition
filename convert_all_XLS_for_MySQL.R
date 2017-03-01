# parent script for converting all tables in PRIMAGRAFTS

# set directory
baseDir = file.path("~","Dropbox","PRoXe","db_transition")
setwd(baseDir)

# read in conversion metadata
library(readxl)
# convert <- read_excel("mark_mysql/conversion_guide.xlsx") #TODO: delete if not used. 

########### -- Create each MySQL table in a separate script -- ###########
# convert primagrafts, ... in this folder to MySQL objects.
source(file.path(baseDir,"convert_all_XLS","create_admin.R"))
source(file.path(baseDir,"convert_all_XLS","create_clinical.R"))
source(file.path(baseDir,"convert_all_XLS","create_tumor.R"))
source(file.path(baseDir,"convert_all_XLS","create_inventory.R")) # TODO. comes from inventory.
# source(file.path(baseDir,"convert_all_XLS","create_pdx.R")) # TODO. Comes from prima only.
# source(file.path(baseDir,"convert_all_XLS","create_pdx_seq.R")) # TODO. Comes from sequencing_tracking and a little from prima.


# TODO: after the second or third of these tables, generalize some actions into functions, depend on common variables, etc.
  # For instance, perhaps read in all precursor tables in one script before starting.


### CRITICAL TODO: SCRIPT SIMILARLY FOR FOREIGN KEY CONSTRAINTS ONLY AT END OF ALL TABLE READ-IN. ###
# also consider adding checks and autoincrements


### Answered: Determine where my MySQL database is stored and if easy to send to Mark.
# stored in SPKs MBP:/usr/local/var/mysql/proxe_test as .frm and .ibd files
# not simple to send, but shouldn't be too difficult:
  # try 'mysqldump' to copy: https://dev.mysql.com/doc/refman/5.7/en/copying-databases.html
  # else try https://mediatemple.net/community/products/dv/204403864/export-and-import-mysql-databases
  # else try http://stackoverflow.com/questions/22447651/copying-mysql-databases-from-one-computer-to-another