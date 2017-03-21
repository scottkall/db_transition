library(readxl)
# library(xlsx)
library(stringr)

# move to PRIMA folder
setwd(file.path(baseDir,"XLS_cleaned"))

# set relevant global variables
TABLE_NAME = "pdx"

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

########## subset conversion guide for only new table. #########

# filter 'convert' for just the rows relevant to the new table
convert_subset <- meta[meta$NewTable==TABLE_NAME | meta$NewColName=="pdx_id",]

if(!any(colnames(df) %in% c("MRN","Sample_ID"))){
  warning("Conditionally dropped MRN and Sample_ID from conversion because did not exist in PRIMAGRAFTS.")
  convert_subset <- convert_subset[!(convert_subset$OrigColumn %in% c("MRN","Sample_ID")),]
}

# warning("TEMPORARY: added subset_index row to convert_subset")
# convert_subset <- rbind(convert_subset, list(NA,NA,NA,NA,"subset","subset_index","INT",NA,0,0,1,0,NA,NA,NA))


########## create draft df from subsetting columns #####

cols_to_keep <- c(convert_subset$OrigColumn,"Derivative")  # specifically included Derivative for below
stopifnot(all(cols_to_keep %in% colnames(df)))
df_subset <- df[,cols_to_keep]


############# Clean up, subset df as necessary to produce subset ################

## create unique 10-digit code per PDX
df_subset$pdx_id <- stringr::str_sub(df$PDX_Name,1,10)

# View(df[df$pdx_id %in% unique(df$pdx_id[duplicated(df$pdx_id)]),]) # view duplicates
# View(df_subset[df_subset$pdx_id %in% unique(df_subset$pdx_id[duplicated(df_subset$pdx_id)]),])

# drop PDX_Name
df_subset$PDX_Name <- NULL

# collapse duplicates -- method: remove original of 'Derivative' lines, then remove that column
duplicated_ids <- unique(df_subset$pdx_id[duplicated(df_subset$pdx_id)])
stopifnot(length(which(df_subset$Derivative == 1)) == length(duplicated_ids)) # confirm assumption
duplicates_to_remove <- which(df_subset$pdx_id %in% duplicated_ids & df_subset$Derivative != 1)
df_subset <- df_subset[-duplicates_to_remove,]
  # df_subset$pdx_id[which(is.na(df_subset$Derivative))] # show which lines are NA for Derivative -- why? I messaged Mark.
# remove 'derivative' column
df_subset$Derivative <- NULL

# convert colnames from OrigColumn to NewColName
  # colnames(df_subset)
  # convert_subset$OrigColumn
  # convert_subset$NewColName
for(i in 1:length(colnames(df_subset))){
  nm <- colnames(df_subset)[i]
  if(nm %in% convert_subset$OrigColumn){
    j <- which(convert_subset$OrigColumn == nm)
    colnames(df_subset)[i] <- convert_subset[j,]$NewColName
  } 
}

# keep only columns in NewColName
cols_to_delete <- which(!(colnames(df_subset) %in% convert_subset$NewColName))
if(length(cols_to_delete)>0){
  warn <- paste("deleting columns:",paste(colnames(df_subset)[cols_to_delete],collapse=", "))
  warning(warn)
  df_subset <- df_subset[-cols_to_delete]
}

# reorder columns
if(any(!is.na(convert_subset$Column_Order))) {
  desired_order <- convert_subset[order(convert_subset$Column_Order),]$NewColName
  df_subset <- df_subset[,desired_order]
}

# add index
# df_subset$subset_index <- 1:nrow(df_subset)
  # commented for now because perhaps not necessary? Else add to conversion_guide and in code above if necessary.


##### write df_subset out as a TSV file for possible read-in to SQL #####

# write.table(df_subset,file = "output_subset.txt",quote = FALSE,sep="\t",na="",row.names=FALSE)
### Temporary: write df_subset out as a CSV file ###
# write.csv(df_subset,file = "output_subset.csv",quote = FALSE,na="",row.names=FALSE)


################ -- Put new table directly into MySQL -- ######################

library(RMySQL)
## ... looks like this requires a working database to which to make a connection.
mydb <- dbConnect(RMySQL::MySQL(), user="scott",password = "proxe123",dbname = "proxe_test",host="127.0.0.1")

## -- Create named field.types colnames vector from filtered 'convert_subset' df. -- ##

# # view order
# convert_subset$NewColName
# colnames(df_subset)
# all(convert_subset$NewColName %in% colnames(df_subset))

# Create field.types list
field.types <- convert_subset$Datatype
names(field.types) <- convert_subset$NewColName
# reorder field.types so it doesn't undo sorting
field.types <- field.types[names(df_subset)]

# Create table in MySQL
dbWriteTable(mydb,name=TABLE_NAME,value=df_subset,field.types=field.types,row.names=FALSE,overwrite=TRUE)
# dbDisconnect(mydb)

### -- denote which is primary key, not null, etc. via dbSendQuery -- ##

# add primary key
if(sum(convert_subset$PrimaryKey)>0){
  stopifnot(sum(convert_subset$PrimaryKey)==1)
  query <- paste0(
    "ALTER TABLE ",TABLE_NAME,
    " ADD PRIMARY KEY (",convert_subset[convert_subset$PrimaryKey == 1,]$NewColName,");"
  )
  print(query)
  dbSendQuery(mydb,query)
}

# add NOT NULL constraints
if(sum(as.numeric(convert_subset$NotNull))>0){
  ind <- which(as.logical(convert_subset$NotNull))
  for (i in ind){
    row <- convert_subset[i,]
    query <- paste(
      "ALTER TABLE",TABLE_NAME,
      "MODIFY",row$NewColName,row$Datatype,"NOT NULL;"
    )
    print(query)
    dbSendQuery(mydb,query)
  }
}

# add UNIQUE constraints
if(sum(as.numeric(convert_subset$Unique))>0){
  ind <- which(as.logical(convert_subset$Unique))
  for (i in ind){
    query <- paste0(
      "ALTER TABLE ",TABLE_NAME,
      " ADD UNIQUE (",convert_subset[i,]$NewColName,");"
    )
    print(query)
    dbSendQuery(mydb,query)
  }
}

### CRITICAL TODO: SCRIPT SIMILARLY FOR FOREIGN KEY CONSTRAINTS ONLY AT END OF ALL TABLE READ-IN. ###
# also consider adding checks and autoincrements
# -- do this at end of parent script: convert_all_XLS_for_MySQL.R

## -- create and add to columns table. -- ##
convert_subset$NewTable = TABLE_NAME
dbWriteTable(mydb,name="columns",value=convert_subset,row.names=FALSE,overwrite=FALSE,append=TRUE)

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
