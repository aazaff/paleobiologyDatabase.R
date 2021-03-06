# Custom functions are camelCase. Arrays, parameters, and arguments are PascalCase
# Dependency functions are not embedded in master functions

######################################### Load Required Libraries ###########################################
# Load Required Libraries
if (require("RCurl")==FALSE) {
	install.packages("RCurl")
	library("RCurl")
	}
if (require("rgdal")==FALSE) {
	install.packages("rgdal")
	library("rgdal")
	}

# A function for downloading data from the Paleobiology database
downloadPBDB<-function(Taxa,StartInterval="Pliocene",StopInterval="Pleistocene") {
	Taxa<-paste(Taxa,collapse=",")
	URL<-paste("https://paleobiodb.org/data1.2/occs/list.csv?base_name=",Taxa,"&interval=",StartInterval,",",StopInterval,"&show=coords,paleoloc,phylo&limit=all",sep="")
	GotURL<-getURL(URL)
	File<-read.csv(text=GotURL,header=T)
	return(File)
	}

# Download timescales from Macrostrat
downloadTime<-function(Timescale) {
	Timescale<-gsub(" ","%20",Timescale)
	URL<-paste("https://dev.macrostrat.org/api/defs/intervals?format=csv&timescale=",Timescale,sep="")
	GotURL<-getURL(URL)
	Intervals<-read.csv(text=GotURL,header=TRUE)
	Midpoint<-apply(Intervals[,c("t_age","b_age")],1,median)
	Intervals<-cbind(Intervals,Midpoint)
	rownames(Intervals)<-Intervals[,"name"]
	return(Intervals)
	}

# Remove subgenera and NAs
cleanRank<-function(DataPBDB,Rank="genus") {
	DataPBDB<-subset(DataPBDB,DataPBDB[,Rank]!="") # Remove NAs
	DataPBDB<-subset(DataPBDB,is.na(DataPBDB[,Rank])!=TRUE) # Remove NAs
	SpaceSeparated<-sapply(as.character(DataPBDB[,Rank]),strsplit," ")
	DataPBDB[,Rank]<-sapply(SpaceSeparated,function(S) S[1])
	return(DataPBDB)
	}

# Assign fossil occurrences to different ages
# Then remove occurrences that are not temporally constrained to a single interval
constrainAges<-function(DataPBDB,Timescale) {
	DataPBDB[,"early_interval"]<-as.character(DataPBDB[,"early_interval"])
	DataPBDB[,"late_interval"]<-as.character(DataPBDB[,"late_interval"])
	for (i in 1:nrow(Timescale)) {
		EarlyPos<-which(DataPBDB[,"max_ma"]>Timescale[i,"t_age"] & DataPBDB[,"max_ma"]<=Timescale[i,"b_age"])
		DataPBDB[EarlyPos,"early_interval"]<-as.character(Timescale[i,"name"])
		LatePos<-which(DataPBDB[,"min_ma"]>=Timescale[i,"t_age"] & DataPBDB[,"min_ma"]<Timescale[i,"b_age"])
		DataPBDB[LatePos,"late_interval"]<-as.character(Timescale[i,"name"])
		}
	DataPBDB<-DataPBDB[DataPBDB[,"early_interval"]==DataPBDB[,"late_interval"],] # Remove taxa that range through
	return(DataPBDB)
	}

# download maps of paleocontinents from Macrostrat
downloadPaleogeography<-function(Age=0) {
	URL<-paste("https://macrostrat.org/api/paleogeography?format=geojson_bare&age=",Age,sep="")
	GotURL<-getURL(URL)
	Map<-readOGR(GotURL,"OGRGeoJSON",verbose=FALSE)
	return(Map)
	}
	
# Find the min and max age range of a taxonomic ranking - e.g., genus.
ageRanges<-function(IntervalPBDB,Taxonomy="genus") {
	IntervalPBDB<-subset(IntervalPBDB,is.na(IntervalPBDB[,Taxonomy])!=TRUE) # Remove NA's
	IntervalPBDB[,Taxonomy]<-factor(IntervalPBDB[,Taxonomy]) # Drop hanging attributes
	PBDBEarly<-tapply(IntervalPBDB[,"max_ma"],IntervalPBDB[,Taxonomy],max) # Calculate max age
	PBDBLate<-tapply(IntervalPBDB[,"min_ma"],IntervalPBDB[,Taxonomy],min) # Calculate min age
	AgesPBDB<-cbind(PBDBEarly,PBDBLate) # Bind ages
	colnames(AgesPBDB)<-c("EarlyAge","LateAge")
	return(data.matrix(AgesPBDB))
	}

# Create a community matrix of samples v. species, using elements within one of the PBDB columns
# (e.g., geoplate, early_interval) as the definition of a sample. This is a presence-absence matrix.
presenceMatrix<-function(DataPBDB,Rows="geoplate",Columns="genus") {
	FinalMatrix<-matrix(0,nrow=length(unique(DataPBDB[,Rows])),ncol=length(unique(DataPBDB[,Columns])))
	rownames(FinalMatrix)<-unique(DataPBDB[,Rows])
	colnames(FinalMatrix)<-unique(DataPBDB[,Columns])
	ColumnPositions<-match(DataPBDB[,Columns],colnames(FinalMatrix))
	RowPositions<-match(DataPBDB[,Rows],rownames(FinalMatrix))
	Positions<-cbind(RowPositions,ColumnPositions)
	FinalMatrix[Positions]<-1
	return(FinalMatrix)
	}


# Create a community matrix of samples v. species, using elements within one of the PBDB columns
# (e.g., geoplate, early_interval) as the definition of a sample. This is an "abundance" matrix which uses
# the number of occurrences.
abundanceMatrix<-function(DataPBDB,Rows="geoplate",Columns="genus") {
	DataPBDB[,Columns]<-as.factor(DataPBDB[,Columns])
	SamplesAbundances<-by(DataPBDB,DataPBDB[,Rows],function(x) table(x[,Columns]))
	FinalMatrix<-sapply(SamplesAbundances,data.matrix)
	rownames(FinalMatrix)<-sort(unique((DataPBDB[,Columns])))
	return(t(FinalMatrix))
	}

# Match PBDB collections to a Macrostrat Unit
# This will function will ideally be re-optimized when v3 of macrostrat goes live, there it is not yet
# suppoted as part of this package.
macrostratMatch<-function(DataPBDB) {
	URL<-paste("https://macrostrat.org/api/fossils?format=csv&age_top=",min(DataPBDB[,"min_ma"]),"&age_bottom=",max(DataPBDB[,"max_ma"]),sep="")
	FossilURL<-getURL(URL)
	CollectionMatches<-read.csv(text=FossilURL,header=T)[,c("unit_id","cltn_id")]
	URL<-paste("https://macrostrat.org/api/units?format=csv&age_top=",min(DataPBDB[,"min_ma"]),"&age_bottom=",max(DataPBDB[,"max_ma"]),sep="")
	UnitURL<-getURL(URL)
	UnitMatches<-read.csv(text=UnitURL,header=T)[,c("unit_id","unit_name")]
	MacrostratData<-merge(CollectionMatches,UnitMatches,by="unit_id")
	MacrostratMatch<-merge(MacrostratData,DataPBDB,by.x="cltn_id",by.y="collection_no")
	return(MacrostratMatch[,c("cltn_id","unit_id","unit_name","occurrence_no","paleolat","paleolng","early_interval","late_interval","phylum","class","order","family","genus")])
	}
	
