

################### OUTLINE #####################
# 1. read in header_data from prima, inventory, seq_tracking.
# 2. find which columns are listed as foreign keys.
# 3. send appropriate sql commands to connect those foregn keys.


library(readxl)
library(stringr)

# move to data folder
setwd(dataDir)

############################################################
# 1. Read in metadata  
############################################################

# 1. For Prima
prima.filename <- dir(".",pattern = glob2rx("PRIMAGRAFTS*xlsx"))
if(length(prima.filename) != 1) stop("too few or too many PRIMAGRAFTS sheets in dropbox")
meta_prima <- read_excel(paste0("./",prima.filename),sheet="Header_Data")

# 2. For Inventory
inv.filename <- dir(".",pattern = glob2rx("PDX_Inventory_*xlsx"))
if(length(inv.filename) != 1) stop("too few or too many Inventory sheets in dropbox")
meta_inv <- read_excel(paste0("./",inv.filename),sheet="Header_Data")

# 3. For Sequencing_checklist
seq.filename <- dir(".",pattern = glob2rx("SEQUENCING_checklist_*xlsx"))
if(length(seq.filename) != 1) stop("too few or too many SEQUENCING_checklist_ sheets in dropbox")
meta_seq <- read_excel(paste0("./",seq.filename),sheet="Header_Data")


############################################################
# 2. Combine and determine which are foreign keys
############################################################


####### Tests #######
# confirm that all have the same # columns
ncol_metas <- sapply(ls(pattern="meta_"),function(item) {ncol(get(item))})
stopifnot(all(ncol_metas==ncol_metas[1]))
# confirm that all have the same column names
colnames_metas <- lapply(ls(pattern="meta_"),function(item){ colnames(get(item))})
colnames_metas[[1]][1] == colnames_metas[[2]][1]
for(i in 2:length(ncol_metas)) {
  stopifnot(all(colnames_metas[[1]]==colnames_metas[[i]]))
}

####### Combine #######
meta <- do.call(rbind, lapply(ls(pattern="meta_"),get))


####### Filter for foreign keys #######
to_modify <- as.data.frame(meta[meta$ForeignKeyBool==TRUE,c("NewTable","NewColName",names(meta)[grep("foreign",names(meta),TRUE)])])


############################################################
# 3. Send commands to Database
############################################################

library(RMySQL)
## ... looks like this requires a working database to which to make a connection.
mydb <- dbConnect(RMySQL::MySQL(), user=sql_user,password = sql_password,dbname = sql_dbname,host="127.0.0.1")

# Filter for tables in db
dbTables <- dbListTables(mydb)
if(!all(c(to_modify$NewTable,to_modify$If_ForeignKey_Table) %in% dbTables)) {
  warning("Some foreign key tables do not exist")
  to_modify <- to_modify[to_modify$NewTable %in% dbTables & to_modify$If_ForeignKey_Table %in% dbTables,]
}

# Turn off foreign key checks
dbGetQuery(mydb,"SET foreign_key_checks = 0;")

# add constraints
# alter table inventory add foreign key (pdx_id) references admin (pdx_id);
if(sum(to_modify$ForeignKeyBool)>0){
  for (i in 1:nrow(to_modify)){
    row <- to_modify[i,]
    query <- paste0(
      "ALTER TABLE ", row$NewTable,
      " ADD FOREIGN KEY (",row$NewColName,") REFERENCES ",
      row$If_ForeignKey_Table," (",row$If_ForeignKey_Name,");"
    )
    print(query)
    dbGetQuery(mydb,query)
  }
}

# Turn on foreign key checks
dbGetQuery(mydb,"SET foreign_key_checks = 1;")

dbDisconnect(mydb)

setwd(baseDir)
