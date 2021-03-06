# Install and load R packages ---------------------------------------------
ipak <- function(pkg){
  new.pkg <- pkg[!(pkg %in% installed.packages()[, "Package"])]
  if (length(new.pkg)) 
    install.packages(new.pkg, dependencies = TRUE)
  sapply(pkg, require, character.only = TRUE)
}
packages <- c("sf", "data.table", "tidyverse", "ggplot2", "ggmap", "mapview")
ipak(packages)

# Define paths
inputPath <- "Input"
outputPath <- "Output"

# Define assessment period - Uncomment the period you want to run the assessment for!
assessmentPeriod <- "2011-2016"
assessmentPeriod <- "2016-2021"

# Create paths
dir.create(inputPath, showWarnings = FALSE, recursive = TRUE)
dir.create(outputPath, showWarnings = FALSE, recursive = TRUE)

# Download and unpack files needed for the assessment --------------------------
download.file.unzip.maybe <- function(url, refetch = FALSE, path = ".") {
  dest <- file.path(path, sub("\\?.+", "", basename(url)))
  if (refetch || !file.exists(dest)) {
    download.file(url, dest, mode = "wb")
    if (tools::file_ext(dest) == "zip") {
      unzip(dest, exdir = path)
    }
  }
}

if (assessmentPeriod == "2011-2016"){
  # Assessment Period 2011-2016
  urls <- c("https://www.dropbox.com/s/poruz8srxfqiflm/AssessmentUnits.zip?dl=1",
          "https://www.dropbox.com/s/05mjl0haig72wrj/Indicators.csv?dl=1",
          "https://www.dropbox.com/s/uikixp822dq3u92/IndicatorUnits.csv?dl=1",
          "https://www.dropbox.com/s/lbo4d24lauyz6gn/UnitGridSize.csv?dl=1",
          "https://www.dropbox.com/s/xqlqhypxbz7mm0c/StationSamplesICE.txt.gz?dl=1",
          "https://www.dropbox.com/s/66rkujevbkvic2q/StationSamplesCTD.txt.gz?dl=1")
} else {
  # Assessment Period 2016-2021
  urls <- c("https://www.dropbox.com/s/4jbqffm2nstma9v/AssessmentUnits.zip?dl=1",
            "https://www.dropbox.com/s/s5pzd8cvksfffgn/Indicators.csv?dl=1",
            "https://www.dropbox.com/s/28wr662sz6jxjox/IndicatorUnits.csv?dl=1",
            "https://www.dropbox.com/s/cs4boo7247p6e13/UnitGridSize.csv?dl=1",
            "https://www.dropbox.com/s/vp04vrl2gk5vxx1/StationSamplesICE.txt.gz?dl=1",
            "https://www.dropbox.com/s/89i1w79lmlab425/StationSamplesCTD.txt.gz?dl=1")
}

files <- sapply(urls, download.file.unzip.maybe, path = inputPath)

unitsFile <- file.path(inputPath, paste0("AssessmentUnits.shp"))
indicatorsFile <- file.path(inputPath, "Indicators.csv")
indicatorUnitsFile <- file.path(inputPath, "IndicatorUnits.csv")
unitGridSizeFile <- file.path(inputPath, "UnitGridSize.csv")
stationSamplesICEFile <- file.path(inputPath, "StationSamplesICE.txt.gz")

# Assessment Units + Grid Units-------------------------------------------------

# Read assessment unit from shape file
units <- st_read(unitsFile)

# Filter for open sea assessment units
units <- units[units$Code %like% 'SEA',]

# Correct Description column name - temporary solution!
colnames(units)[2] <- "Description"

# Correct Åland Sea ascii character - temporary solution!
units[14,2] <- 'Åland Sea'

# Include stations from position 55.86667+-0.01667 12.75+-0.01667 which will include the Danish station KBH/DMU 431 and the Swedish station Wlandskrona into assessment unit 3/SEA-003
units[3,] <- st_union(units[3,],st_as_sfc("POLYGON((12.73333 55.85,12.73333 55.88334,12.76667 55.88334,12.76667 55.85,12.73333 55.85))", crs = 4326))

# Assign IDs
units$UnitID = 1:nrow(units)

# Identify invalid geometries
st_is_valid(units)

# Transform projection into ETRS_1989_LAEA
units <- st_transform(units, crs = 3035)

# Calculate area
units$UnitArea <- st_area(units)

# Identify invalid geometries
st_is_valid(units)

# Make geometries valid by doing the buffer of nothing trick
#units <- sf::st_buffer(units, 0.0)

# Identify overlapping assessment units
#st_overlaps(units)

# Make grid units
make.gridunits <- function(units, gridSize) {
  units <- st_transform(units, crs = 3035)
  
  bbox <- st_bbox(units)
  
  xmin <- floor(bbox$xmin / gridSize) * gridSize
  ymin <- floor(bbox$ymin / gridSize) * gridSize
  xmax <- ceiling(bbox$xmax / gridSize) * gridSize
  ymax <- ceiling(bbox$ymax / gridSize) * gridSize
  
  xn <- (xmax - xmin) / gridSize
  yn <- (ymax - ymin) / gridSize
  
  grid <- st_make_grid(units, cellsize = gridSize, c(xmin, ymin), n = c(xn, yn), crs = 3035) %>%
    st_sf()
  
  grid$GridID = 1:nrow(grid)
  
  gridunits <- st_intersection(grid, units)
  
  gridunits$Area <- st_area(gridunits)
  
  return(gridunits)
}

gridunits10 <- make.gridunits(units, 10000)
gridunits30 <- make.gridunits(units, 30000)

unitGridSize <-  fread(input = unitGridSizeFile) %>% setkey(UnitID)

a <- merge(unitGridSize[GridSize == 10000], gridunits10 %>% select(UnitID, GridID, GridArea = Area))
b <- merge(unitGridSize[GridSize == 30000], gridunits30 %>% select(UnitID, GridID, GridArea = Area))
gridunits <- st_as_sf(rbindlist(list(a,b)))
rm(a,b)

# Plot
#ggplot() + geom_sf(data = units) + coord_sf()
#ggplot() + geom_sf(data = gridunits10) + coord_sf()
#ggplot() + geom_sf(data = gridunits30) + coord_sf()
#ggplot() + geom_sf(data = gridunits) + coord_sf()

# Read stationSamples ----------------------------------------------------------
stationSamples <- fread(input = stationSamplesICEFile, sep = "\t", na.strings = "NULL", stringsAsFactors = FALSE, header = TRUE, check.names = TRUE)

# !!! We could separate stations from samples here, do the spatial and then rejoin samples again ... migth be more rubust
#stationSamples[, StationID := .GRP, by = .(Cruise, StationNumber, Year, Month, Day, Hour, Minute, Latitude..degrees_north., Longitude..degrees_east.)]
#stationSamples[, .N, .(ID, Cruise, StationNumber, Year, Month, Day, Hour, Minute, Latitude..degrees_north., Longitude..degrees_east.)]

# Make stations spatial keeping original latitude/longitude
stationSamples <- st_as_sf(stationSamples, coords = c("Longitude..degrees_east.", "Latitude..degrees_north."), remove = FALSE, crs = 4326)

# Transform projection into ETRS_1989_LAEA
stationSamples <- st_transform(stationSamples, crs = 3035)

# Classify stations into assessment units
#stationSamples$UnitID <- st_intersects(stationSamples, units) %>% as.numeric()

# Classify stations into 10 and 30k gridunits
#stationSamples <- st_join(stationSamples, gridunits10 %>% select(GridID.10k = GridID, Area.10k = Area), join = st_intersects)
#stationSamples <- st_join(stationSamples, gridunits30 %>% select(GridID.30k = GridID, Area.30k = Area), join = st_intersects)
stationSamples <- st_join(stationSamples, st_cast(gridunits), join = st_intersects)

# Remove spatial column
stationSamples <- st_set_geometry(stationSamples, NULL)

# Read indicator configs -------------------------------------------------------
indicators <- fread(input = indicatorsFile) %>% setkey(IndicatorID) 
indicatorUnits <- fread(input = indicatorUnitsFile) %>% setkey(IndicatorID, UnitID)

wk1list = list()
wk2list = list()

# Loop indicators --------------------------------------------------------------
for(i in 1:nrow(indicators)){
  indicatorID <- indicators[i, IndicatorID]
  criteriaID <- indicators[i, CriteriaID]
  name <- indicators[i, Name]
  year.min <- indicators[i, YearMin]
  year.max <- indicators[i, YearMax]
  month.min <- indicators[i, MonthMin]
  month.max <- indicators[i, MonthMax]
  depth.min <- indicators[i, DepthMin]
  depth.max <- indicators[i, DepthMax]
  metric <- indicators[i, Metric]
  response <- indicators[i, Response]

  # Copy data
  wk <- as.data.table(stationSamples)  
  
  # Create Period
  wk[, Period := ifelse(month.min > month.max & Month >= month.min, Year + 1, Year)]
  
  # Create Indicator
  if (name == 'Dissolved Inorganic Nitrogen') {
    wk$ES <- apply(wk[, list(Nitrate..umol.l., Nitrite..umol.l., Ammonium..umol.l.)], 1, function(x){
      if (all(is.na(x)) | is.na(x[1])) {
        NA
      }
      else {
        sum(x, na.rm = TRUE)
      }
    })
  }
  else if (name == 'Dissolved Inorganic Phosphorus') {
    wk[,ES := Phosphate..umol.l.]
  }
  else if (name == 'Chlorophyll a') {
    wk[, ES := Chlorophyll.a..ug.l.]
  }
  else if (name == 'Secchi Depth') {
    wk[, ES := Secchi..m..METAVAR.DOUBLE]
  }
  else if (name == "Total Nitrogen") {
    wk[, ES := Total.Nitrogen..umol.l.]
  }
  else if (name == "Total Phosphorus") {
    wk[, ES := Total.Phosphorus..umol.l.]
  }
  else {
    next
  }
  
  # Add unit grid size
  wk <- wk[unitGridSize, on="UnitID", nomatch=0]
  
  # Filter stations rows and columns --> UnitID, GridID, GridArea, Period, Month, StationID, Depth, Temperature, Salinity, ES
  if (month.min > month.max) {
    wk0 <- wk[
      (Period >= year.min & Period <= year.max) &
        (Month >= month.min | Month <= month.max) &
        (Depth..m.db..PRIMARYVAR.DOUBLE >= depth.min & Depth..m.db..PRIMARYVAR.DOUBLE <= depth.max) &
        !is.na(ES) & 
        !is.na(UnitID),
      .(IndicatorID = indicatorID, UnitID, GridSize, GridID, GridArea, Period, Month, StationID, Depth = Depth..m.db..PRIMARYVAR.DOUBLE, Temperature = Temperature..degC., Salinity = Salinity..., ES)]
  } else {
    wk0 <- wk[
      (Period >= year.min & Period <= year.max) &
        (Month >= month.min & Month <= month.max) &
        (Depth..m.db..PRIMARYVAR.DOUBLE >= depth.min & Depth..m.db..PRIMARYVAR.DOUBLE <= depth.max) &
        !is.na(ES) & 
        !is.na(UnitID),
      .(IndicatorID = indicatorID, UnitID, GridSize, GridID, GridArea, Period, Month, StationID, Depth = Depth..m.db..PRIMARYVAR.DOUBLE, Temperature = Temperature..degC., Salinity = Salinity..., ES)]
  }

  # Calculate station mean --> UnitID, GridID, GridArea, Period, Month, ES, SD, N
  wk1 <- wk0[, .(ES = mean(ES), SD = sd(ES), N = .N), keyby = .(IndicatorID, UnitID, GridID, GridArea, Period, Month, StationID)]
  
  # Calculate annual mean --> UnitID, Period, ES, SD, N, NM
  wk2 <- wk1[, .(ES = mean(ES), SD = sd(ES), N = .N, NM = uniqueN(Month)), keyby = .(IndicatorID, UnitID, Period)]

  wk1list[[i]] <- wk1
  wk2list[[i]] <- wk2
}

# Combine station and annual indicator results
wk1 <- rbindlist(wk1list)
wk2 <- rbindlist(wk2list)

# Combine with indicator and indicator unit configuration tables
wk3 <- indicators[indicatorUnits[wk2]]

# Standard Error
wk3[, SE := SD / sqrt(N)]

# 95 % Confidence Interval
wk3[, CI := qnorm(0.975) * SE]

# Calculate Eutrophication Ratio (ER)
wk3[, ER := ifelse(Response == 1, ES / ET, ET / ES)]

# Calculate (BEST)
wk3[, BEST := ifelse(Response == 1, ET / (1 + ACDEV / 100), ET / (1 - ACDEV / 100))]

# Calculate Ecological Quality Ratio (ERQ)
wk3[, EQR := ifelse(Response == 1, ifelse(BEST > ES, 1, BEST / ES), ifelse(ES > BEST, 1, ES / BEST))]

# Calculate Ecological Quality Ratio Boundaries (ERQ_HG/GM/MP/PB)
wk3[, EQR_GM := ifelse(Response == 1, 1 / (1 + ACDEV / 100), 1 - ACDEV / 100)]
wk3[, EQR_HG := 0.5 * 0.95 + 0.5 * EQR_GM]
wk3[, EQR_PB := 2 * EQR_GM - 0.95]
wk3[, EQR_MP := 0.5 * EQR_GM + 0.5 * EQR_PB]

# Calculate Ecological Quality Ratio Scaled (EQRS)
wk3[, EQRS := ifelse(EQR <= EQR_PB, (EQR - 0) * (0.2 - 0) / (EQR_PB - 0) + 0,
                     ifelse(EQR <= EQR_MP, (EQR - EQR_PB) * (0.4 - 0.2) / (EQR_MP - EQR_PB) + 0.2,
                            ifelse(EQR <= EQR_GM, (EQR - EQR_MP) * (0.6 - 0.4) / (EQR_GM - EQR_MP) + 0.4,
                                   ifelse(EQR <= EQR_HG, (EQR - EQR_GM) * (0.8 - 0.6) / (EQR_HG - EQR_GM) + 0.6,
                                          (EQR - EQR_HG) * (1 - 0.8) / (1 - EQR_HG) + 0.8))))]

wk3[, EQRS_Class := ifelse(EQRS >= 0.8, "High",
                           ifelse(EQRS >= 0.6, "Good",
                                  ifelse(EQRS >= 0.4, "Moderate",
                                         ifelse(EQRS >= 0.2, "Poor","Bad"))))]

# Calculate General Temporal Confidence (GTC) - Confidence in number of annual observations
wk3[, GTC := ifelse(N > GTC_HM, 100, ifelse(N < GTC_ML, 0, 50))]

# Calculate Number of Months Potential
wk3[, NMP := ifelse(MonthMin > MonthMax, 12 - MonthMin + 1 + MonthMax, MonthMax - MonthMin + 1)]

# Calculate Specific Temporal Confidence (STC) - Confidence in number of annual missing months
wk3[, STC := ifelse(NMP - NM <= STC_HM, 100, ifelse(NMP - NM >= STC_ML, 0, 50))]

# Calculate General Spatial Confidence (GSC) - Confidence in number of annual observations per number of grids 

# Calculate Specific Spatial Confidence (SSC) - Confidence in area of sampled grid units as a percentage to the total unit area
a <- wk1[, .N, keyby = .(IndicatorID, UnitID, Period, GridID, GridArea)] # UnitGrids
b <- a[, .(GridArea = sum(as.numeric(GridArea))), keyby = .(IndicatorID, UnitID, Period)] #GridAreas
c <- as.data.table(units)[, .(UnitArea = as.numeric(UnitArea)), keyby = .(UnitID)] # UnitAreas
d <- c[b, on = .(UnitID = UnitID)] # UnitAreas ~ GridAreas
wk3 <- wk3[d[,.(IndicatorID, UnitID, Period, UnitArea, GridArea)], on = .(IndicatorID = IndicatorID, UnitID = UnitID, Period = Period)]
wk3[, SSC := ifelse(GridArea / UnitArea * 100 > SSC_HM, 100, ifelse(GridArea / UnitArea * 100 < SSC_ML, 0, 50))]
rm(a,b,c,d)

# Calculate assessment ES --> UnitID, Period, ES, SD, N, GTC, STC, GSC, SSC
wk4 <- wk3[, .(Period = min(Period) * 10000 + max(Period), ES = mean(ES), SD = sd(ES), N = .N, N_OBS = sum(N), GTC = mean(GTC), STC = mean(STC), SSC = mean(SSC)), .(IndicatorID, UnitID)]

# Add Year Count where STC = 100
wk4 <- wk3[STC == 100, .(NSTC100 = .N), .(IndicatorID, UnitID)][wk4, on = .(IndicatorID, UnitID)]
wk4[, STC := ifelse(!is.na(NSTC100) & NSTC100 >= N/2, 100, STC)]

wk4 <- wk4[, TC := (GTC + STC) / 2]

wk4 <- wk4[, SC := SSC]

wk4 <- wk4[, C := (TC + SC) / 2]

# Combine with indicator and indicator unit configuration tables
wk5 <- indicators[indicatorUnits[wk4]]

# Standard Error
wk5[, SE := SD / sqrt(N)]

# 95 % Confidence Interval
wk5[, CI := qnorm(0.975) * SE]

#-------------------------------------------------------------------------------
# Accuracy Confidence Assessment
# ------------------------------------------------------------------------------

# Accuracy Confidence Level for Non-Problem Area
wk5[, ACL_NPA := ifelse(Response == 1, pnorm(ET, ES, SD), pnorm(ES, ET, SD))]

# Accuracy Confidence Level for Problem Area
wk5[, ACL_PA := 1 - ACL_NPA]

# Accuracy Confidence Level Area Class
wk5[, ACLAC := ifelse(ACL_NPA > 0.5, 1, ifelse(ACL_NPA < 0.5, 3, 2))]

# Accuracy Confidence Level
wk5[, ACL := ifelse(ACL_NPA > ACL_PA, ACL_NPA, ACL_PA)]

# Accuracy Confidence Level Class
wk5[, ACLC := ifelse(ACL > 0.9, 100, ifelse(ACL < 0.7, 0, 50))]

# ------------------------------------------------------------------------------

# Standard Error using number of observations behind the annual mean !!!
wk5[, SE_OBS := SD / sqrt(N_OBS)]

# Accuracy Confidence Level for Non-Problem Area
wk5[, ACL_NPA_OBS := ifelse(Response == 1, pnorm(ET, ES, SE_OBS), pnorm(ES, ET, SE_OBS))]

# Accuracy Confidence Level for Problem Area
wk5[, ACL_PA_OBS := 1 - ACL_NPA_OBS]

# Accuracy Confidence Level Area Class
wk5[, ACLAC_OBS := ifelse(ACL_NPA_OBS > 0.5, 1, ifelse(ACL_NPA_OBS < 0.5, 3, 2))]

# Accuracy Confidence Level
wk5[, ACL_OBS := ifelse(ACL_NPA_OBS > ACL_PA_OBS, ACL_NPA_OBS, ACL_PA_OBS)]

# Accuracy Confidence Level Class
wk5[, ACLC_OBS := ifelse(ACL_OBS > 0.9, 100, ifelse(ACL_OBS < 0.7, 0, 50))]

# ------------------------------------------------------------------------------

# Calculate Eutrophication Ratio (ER)
wk5[, ER := ifelse(Response == 1, ES / ET, ET / ES)]

# Calculate (BEST)
wk5[, BEST := ifelse(Response == 1, ET / (1 + ACDEV / 100), ET / (1 - ACDEV / 100))]

# Calculate Ecological Quality Ratio (ERQ)
wk5[, EQR := ifelse(Response == 1, ifelse(BEST > ES, 1, BEST / ES), ifelse(ES > BEST, 1, ES / BEST))]

# Calculate Ecological Quality Ratio Boundaries (ERQ_HG/GM/MP/PB)
wk5[, EQR_GM := ifelse(Response == 1, 1 / (1 + ACDEV / 100), 1 - ACDEV / 100)]
wk5[, EQR_HG := 0.5 * 0.95 + 0.5 * EQR_GM]
wk5[, EQR_PB := 2 * EQR_GM - 0.95]
wk5[, EQR_MP := 0.5 * EQR_GM + 0.5 * EQR_PB]

# Calculate Ecological Quality Ratio Scaled (EQRS)
wk5[, EQRS := ifelse(EQR <= EQR_PB, (EQR - 0) * (0.2 - 0) / (EQR_PB - 0) + 0,
                     ifelse(EQR <= EQR_MP, (EQR - EQR_PB) * (0.4 - 0.2) / (EQR_MP - EQR_PB) + 0.2,
                            ifelse(EQR <= EQR_GM, (EQR - EQR_MP) * (0.6 - 0.4) / (EQR_GM - EQR_MP) + 0.4,
                                   ifelse(EQR <= EQR_HG, (EQR - EQR_GM) * (0.8 - 0.6) / (EQR_HG - EQR_GM) + 0.6,
                                          (EQR - EQR_HG) * (1 - 0.8) / (1 - EQR_HG) + 0.8))))]

wk5[, EQRS_Class := ifelse(EQRS >= 0.8, "High",
                           ifelse(EQRS >= 0.6, "Good",
                                  ifelse(EQRS >= 0.4, "Moderate",
                                         ifelse(EQRS >= 0.2, "Poor","Bad"))))]

# Criteria ---------------------------------------------------------------------

# Criteria result as a simple average of the indicators in each category per unit - CategoryID, UnitID, N, ER, EQR, EQRS, C
wk6 <- wk5[!is.na(ER), .(.N, ER = mean(ER), EQR = mean(EQR), EQRS = mean(EQRS), C = mean(C)), .(CriteriaID, UnitID)]

# Criteria result as a weighted average of the indicators in each category per unit - CategoryID, UnitID, N, ER, EQR, EQRS, C
#wk6 <- wk5[!is.na(ER), .(.N, ER = weighted.mean(ER, IW, na.rm = TRUE), EQR = weighted.mean(EQR, IW, na.rm = TRUE), EQRS = weighted.mean(EQRS, IW, na.rm = TRUE), C = weighted.mean(C, IW, na.rm = TRUE)), .(CriteriaID, UnitID)]

wk7 <- dcast(wk6, UnitID ~ CriteriaID, value.var = c("N","ER","EQR","EQRS","C"))

# Assessment -------------------------------------------------------------------

# Assessment result - UnitID, N, ER, EQR, EQRS, C
wk8 <- wk6[, .(.N, ER = max(ER), EQR = min(EQR), EQRS = min(EQRS), C = mean(C)), (UnitID)] %>% setkey(UnitID)

wk9 <- wk7[wk8, on = .(UnitID = UnitID), nomatch=0]

wk9[, EQRS_Class := ifelse(EQRS >= 0.8, "High",
                           ifelse(EQRS >= 0.6, "Good",
                                  ifelse(EQRS >= 0.4, "Moderate",
                                         ifelse(EQRS >= 0.2, "Poor","Bad"))))]

# Write results
fwrite(wk3, file = file.path(outputPath, "Annual_Indicator.csv"))
fwrite(wk5, file = file.path(outputPath, "Assessment_Indicator.csv"))
fwrite(wk9, file = file.path(outputPath, "Assessment.csv"))

# Create plots
EQRS_Class_colors <- c("#3BB300", "#99FF66", "#FFCABF", "#FF8066", "#FF0000")
EQRS_Class_limits <- c("High", "Good", "Moderate", "Poor", "Bad")
EQRS_Class_labels <- c(">= 0.8 - 1.0 (High)", ">= 0.6 - 0.8 (Good)", ">= 0.4 - 0.6 (Moderate)", ">= 0.2 - 0.4 (Poor)", ">= 0.0 - 0.2 (Bad)")

#basemap <- get_map(location=c(lon = -1, lat = 53), zoom = 5)

# Assessment map
wk <- merge(units, wk9, all.x = TRUE)

ggplot(wk) +
  ggtitle(label = paste0("Eutrophication Status ", assessmentPeriod)) +
  geom_sf(aes(fill = EQRS_Class)) +
  scale_fill_manual(name = "EQRS", values = EQRS_Class_colors, limits = EQRS_Class_limits, labels = EQRS_Class_labels)

ggsave(file.path(outputPath, "Assessment_Map.png"), width = 12, height = 9, dpi = 300)

# Create Assessment Indicator maps
for (i in 1:nrow(indicators)) {
  indicatorID <- indicators[i, IndicatorID]
  indicatorCode <- indicators[i, Code]
  indicatorName <- indicators[i, Name]
  indicatorYearMin <- indicators[i, YearMin]
  indicatorYearMax <- indicators[i, YearMax]
  indicatorMonthMin <- indicators[i, MonthMin]
  indicatorMonthMax <- indicators[i, MonthMax]
  indicatorDepthMin <- indicators[i, DepthMin]
  indicatorDepthMax <- indicators[i, DepthMax]
  indicatorYearMin <- indicators[i, YearMin]
  indicatorMetric <- indicators[i, Metric]
  
  title <- paste0("Eutrophication Status ", indicatorYearMin, "-", indicatorYearMax)
  subtitle <- paste0(indicatorName, " (", indicatorCode, ")", "\n")
  subtitle <- paste0(subtitle, "Months: ", indicatorMonthMin, "-", indicatorMonthMax, ", ")
  subtitle <- paste0(subtitle, "Depths: ", indicatorDepthMin, "-", indicatorDepthMax, ", ")
  subtitle <- paste0(subtitle, "Metric: ", indicatorMetric)
  fileName <- gsub(":", "", paste0("Assessment_Indicator_Map_", indicatorCode, ".png"))
  
  wk <- wk5[IndicatorID == indicatorID] %>% setkey(UnitID)

  wk <- merge(units, wk, by = "UnitID", all.x = TRUE)
  
  ggplot(wk) +
    labs(title = title , subtitle = subtitle) +
    geom_sf(aes(fill = EQRS_Class)) +
    scale_fill_manual(name = "EQRS", values = EQRS_Class_colors, limits = EQRS_Class_limits, labels = EQRS_Class_labels)
  
  ggsave(file.path(outputPath, fileName), width = 12, height = 9, dpi = 300)
}

# Create Annual Indicator bar charts
for (i in 1:nrow(indicators)) {
  indicatorID <- indicators[i, IndicatorID]
  indicatorCode <- indicators[i, Code]
  indicatorName <- indicators[i, Name]
  indicatorUnit <- indicators[i, Units]
  indicatorYearMin <- indicators[i, YearMin]
  indicatorYearMax <- indicators[i, YearMax]
  indicatorMonthMin <- indicators[i, MonthMin]
  indicatorMonthMax <- indicators[i, MonthMax]
  indicatorDepthMin <- indicators[i, DepthMin]
  indicatorDepthMax <- indicators[i, DepthMax]
  indicatorYearMin <- indicators[i, YearMin]
  indicatorMetric <- indicators[i, Metric]
  for (j in 1:nrow(units)) {
    unitID <- as.data.table(units)[j, UnitID]
    unitCode <- as.data.table(units)[j, Code]
    unitName <- as.data.table(units)[j, Description]
    
    title <- paste0("Eutrophication State [ES, CI, N] and Threshold [ET] ", indicatorYearMin, "-", indicatorYearMax)
    subtitle <- paste0(indicatorName, " (", indicatorCode, ")", " in ", unitName, " (", unitCode, ")", "\n")
    subtitle <- paste0(subtitle, "Months: ", indicatorMonthMin, "-", indicatorMonthMax, ", ")
    subtitle <- paste0(subtitle, "Depths: ", indicatorDepthMin, "-", indicatorDepthMax, ", ")
    subtitle <- paste0(subtitle, "Metric: ", indicatorMetric, ", ")
    subtitle <- paste0(subtitle, "Unit: ", indicatorUnit)
    fileName <- gsub(":", "", paste0("Annual_Indicator_Bar_", indicatorCode, "_", unitCode, ".png"))
    
    wk <- wk3[IndicatorID == indicatorID & UnitID == unitID]
    
    if (nrow(wk) > 0) {
      ggplot(wk, aes(x = factor(Period, levels = indicatorYearMin:indicatorYearMax), y = ES)) +
        labs(title = title , subtitle = subtitle) +
        geom_col() +
        geom_text(aes(label = N), vjust = -0.25, hjust = -0.25) +
        geom_errorbar(aes(ymin = ES - CI, ymax = ES + CI), width = .2) +
        geom_hline(aes(yintercept = ET)) +
        scale_x_discrete(NULL, factor(indicatorYearMin:indicatorYearMax), drop=FALSE) +
        scale_y_continuous(NULL)
      
      ggsave(file.path(outputPath, fileName), width = 12, height = 9, dpi = 300)
    }
  }
}
