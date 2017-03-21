library(readxl)
# library(xlsx)
library(stringr)

# move to PRIMA folder
setwd(file.path(baseDir,"XLS_cleaned"))

# set relevant global variables
TABLE_NAME = "admin"

# read in metadata
prima.filename <- dir(".",pattern = glob2rx("PRIMAGRAFTS*xlsx"))
if(length(prima.filename) != 1) stop("too few or too many PRIMAGRAFTS sheets in dropbox")
meta <- read_excel(paste0("./",prima.filename),sheet="Header_Data")

df <- read_excel(paste0("./",prima.filename),sheet="Injected",
  col_types =rep("text",nrow(meta)))

# convert column in 'meta' to specify type as "blank", "numeric", "date" or "text" for read_excel()
  # original types: "character" "date" "factor" "logical" "numeric"  
stopifnot(all(names(levels(meta$read_excel_type)) %in% c("character","factor","logical","numeric")))
meta$read_excel_type[meta$read_excel_type %in% c("character","factor")] <- "text"
meta$read_excel_type[meta$read_excel_type %in% c("logical","numeric")] <- "numeric"

#TODO here: consider writing a few lines of code that read in df naively, then compare col names with 'meta' and throw a detailed bidirectional setdiff() error if they don't match.

# read in data, returning difference with meta if error.
# try(expr={ # TODO: implement try-else-print-debugging
df <- read_excel(paste0("./",prima.filename),sheet="Injected",
  col_types =rep("text",nrow(meta))) # meta$read_excel_type)
# })
df <- as.data.frame(df) # added because the default class of read_excel output is ‘tbl_df’, ‘tbl’ and 'data.frame' which is incompatible with FUN of convert.magic() 8/2016

# # convert column names from PRIMAGRAFTS name to desired PRoXe name
#   # order 'meta' by 'meta$Interal_Column_Header' matching names(df)
meta <- meta[match(names(df),meta$Internal_Column_Header),]
if(!all(names(df) == meta$Internal_Column_Header)) stop("ordering incorrect")
# names(df) <- meta$PRoXe_Column_Header ## want to keep original for now.

# convert numeric columns in meta$read_excel_type to numeric
df[,which(meta$read_excel_type == "numeric")] <- as.data.frame(lapply(df[,which(meta$read_excel_type == "numeric")],as.numeric))

# See conversion_guide.xls in PRoXe_app/db_transition/mark_mysql. Mark will fill out. Read and use this to convert data.

########## subset conversion guide for only admin table. #########

# filter metadata for just the 'admin' table
# convert_admin <- convert[convert$NewTable=="admin",] # TODO: delete if works.
convert_admin <- meta[meta$NewTable==TABLE_NAME,]

if(!any(colnames(df) %in% c("MRN","Sample_ID"))){
  warning("Conditionally dropped MRN and Sample_ID from conversion because did not exist in PRIMAGRAFTS.")
  convert_admin <- convert_admin[!(convert_admin$OrigColumn %in% c("MRN","Sample_ID")),]
}

# warning("TEMPORARY: added admin_index row to convert_admin")
# convert_admin <- rbind(convert_admin, list(NA,NA,NA,NA,"admin","admin_index","INT",NA,0,0,1,0,NA,NA,NA))


########## create draft df from subsetting columns #####

cols_to_keep <- c(convert_admin$OrigColumn,"Derivative")  # specifically included Derivative for below
stopifnot(all(cols_to_keep %in% colnames(df)))
df_admin <- df[,cols_to_keep]


############# Clean up, subset df as necessary to produce admin ################

## create unique 10-digit code per PDX
df_admin$pdx_id <- stringr::str_sub(df$PDX_Name,1,10)

# View(df[df$pdx_id %in% unique(df$pdx_id[duplicated(df$pdx_id)]),]) # view duplicates
# View(df_admin[df_admin$pdx_id %in% unique(df_admin$pdx_id[duplicated(df_admin$pdx_id)]),])

# drop PDX_Name
df_admin$PDX_Name <- NULL

# collapse duplicates -- method: remove original of 'Derivative' lines, then remove that column
duplicated_ids <- unique(df_admin$pdx_id[duplicated(df_admin$pdx_id)])
stopifnot(length(which(df_admin$Derivative == 1)) == length(duplicated_ids)) # confirm assumption
duplicates_to_remove <- which(df_admin$pdx_id %in% duplicated_ids & df_admin$Derivative != 1)
df_admin <- df_admin[-duplicates_to_remove,]
  # df_admin$pdx_id[which(is.na(df_admin$Derivative))] # show which lines are NA for Derivative -- why? I messaged Mark.
# remove 'derivative' column
df_admin$Derivative <- NULL

# convert colnames from OrigColumn to NewColName
  # colnames(df_admin)
  # convert_admin$OrigColumn
  # convert_admin$NewColName
for(i in 1:length(colnames(df_admin))){
  nm <- colnames(df_admin)[i]
  if(nm %in% convert_admin$OrigColumn){
    j <- which(convert_admin$OrigColumn == nm)
    colnames(df_admin)[i] <- convert_admin[j,]$NewColName
  } 
}

# keep only columns in NewColName
cols_to_delete <- which(!(colnames(df_admin) %in% convert_admin$NewColName))
if(length(cols_to_delete)>0){
  warn <- paste("deleting columns:",paste(colnames(df_admin)[cols_to_delete],collapse=", "))
  warning(warn)
  df_admin <- df_admin[-cols_to_delete]
}

# reorder columns
if(any(!is.na(convert_admin$Column_Order))) {
  desired_order <- convert_admin[order(convert_admin$Column_Order),]$NewColName
  df_admin <- df_admin[,desired_order]
}

# add index
# df_admin$admin_index <- 1:nrow(df_admin)
  # commented for now because perhaps not necessary? Else add to conversion_guide and in code above if necessary.


##### write df_admin out as a TSV file for possible read-in to SQL #####

# write.table(df_admin,file = "output_admin.txt",quote = FALSE,sep="\t",na="",row.names=FALSE)
### Temporary: write df_admin out as a CSV file ###
# write.csv(df_admin,file = "output_admin.csv",quote = FALSE,na="",row.names=FALSE)


########### -- Prep metadata for column metadata table -- ##############




################ -- Put 'admin' directly into MySQL -- ######################

library(RMySQL)
## ... looks like this requires a working database to which to make a connection.
mydb <- dbConnect(RMySQL::MySQL(), user="scott",password = "proxe123",dbname = "proxe_test",host="127.0.0.1")

## -- Create named field.types colnames vector from filtered 'convert_admin' df. -- ##

# # view order
# convert_admin$NewColName
# colnames(df_admin)
# all(convert_admin$NewColName %in% colnames(df_admin))

# Create field.types list
field.types <- convert_admin$Datatype
names(field.types) <- convert_admin$NewColName
# reorder field.types so it doesn't undo sorting
field.types <- field.types[names(df_admin)]

# Create table in MySQL
dbWriteTable(mydb,name=TABLE_NAME,value=df_admin,field.types=field.types,row.names=FALSE,overwrite=TRUE)
# dbDisconnect(mydb)

### -- denote which is primary key, not null, etc. via dbSendQuery -- ##

# add primary key
if(sum(convert_admin$PrimaryKey)>0){
  stopifnot(sum(convert_admin$PrimaryKey)==1)
  query <- paste0(
    "ALTER TABLE ",TABLE_NAME,
    " ADD PRIMARY KEY (",convert_admin[convert_admin$PrimaryKey == 1,]$NewColName,");"
  )
  print(query)
  dbSendQuery(mydb,query)
}

# add NOT NULL constraints
if(sum(as.numeric(convert_admin$NotNull))>0){
  ind <- which(as.logical(convert_admin$NotNull))
  for (i in ind){
    row <- convert_admin[i,]
    query <- paste(
      "ALTER TABLE",TABLE_NAME,
      "MODIFY",row$NewColName,row$Datatype,"NOT NULL;"
    )
    print(query)
    dbSendQuery(mydb,query)
  }
}

# add UNIQUE constraints
if(sum(as.numeric(convert_admin$Unique))>0){
  ind <- which(as.logical(convert_admin$Unique))
  for (i in ind){
    query <- paste0(
      "ALTER TABLE ",TABLE_NAME,
      " ADD UNIQUE (",convert_admin[i,]$NewColName,");"
    )
    print(query)
    dbSendQuery(mydb,query)
  }
}

# create and add to columns table.
dbWriteTable(mydb,name="columns",value=convert_admin,row.names=FALSE,overwrite=TRUE)


### CRITICAL TODO: SCRIPT SIMILARLY FOR FOREIGN KEY CONSTRAINTS ONLY AT END OF ALL TABLE READ-IN. ###
# also consider adding checks and autoincrements
# -- do this at end of parent script: convert_all_XLS_for_MySQL.R

dbDisconnect(mydb)

################### -- Appendix: RMySQL examples -- ##################
if(F){
  if (mysqlHasDefault()) {
    # connect to a database and load some data
    con <- dbConnect(RMySQL::MySQL(), dbname = "test")
    dbWriteTable(con, "USArrests", datasets::USArrests, overwrite = TRUE)
    
    # query
    rs <- dbSendQuery(con, "SELECT * FROM USArrests")
    d1 <- dbFetch(rs, n = 10)      # extract data in chunks of 10 rows
    dbHasCompleted(rs)
    d2 <- dbFetch(rs, n = -1)      # extract all remaining data
    dbHasCompleted(rs)
    dbClearResult(rs)
    dbListTables(con)
    
    # clean up
    dbRemoveTable(con, "USArrests")
    dbDisconnect(con)
  }
}
