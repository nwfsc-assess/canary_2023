##################################################################################################
#
#	Create composition data for commercial fleets
# 		
#		Written by Brian Langseth
#
##################################################################################################

#devtools::install_github("pfmc-assess/PacFIN.Utilities")
library(PacFIN.Utilities)
library(ggplot2)

dir = "//nwcfile/FRAM/Assessments/Assessment Data/2023 Assessment Cycle/canary rockfish/PacFIN data"

#User directories
if(Sys.getenv("USERNAME") == "Brian.Langseth") {
  git_dir <- "U:/Stock assessments/canary_2023/"
}

################################
#Load PacFIN BDS data and set up data
################################
load(file.path(dir, "PacFIN.CNRY.bds.08.May.2023.RData"))
pacfin <- bds.pacfin
pacfin <- pacfin[pacfin$SAMPLE_YEAR < 2023,] #remove 2023

# Load in the current weight-at-length estimates by sex
wlcoef <- utils::read.csv(file.path(git_dir, "data", "W_L_pars.csv"), header = TRUE)
fa = wlcoef[wlcoef$Sex=="F","A"] 
ma = wlcoef[wlcoef$Sex=="M","A"]
ua = wlcoef[wlcoef$Sex=="U","A"]
fb = wlcoef[wlcoef$Sex=="F","B"] 
mb = wlcoef[wlcoef$Sex=="M","B"] 
ub = wlcoef[wlcoef$Sex=="U","B"] 

# Read in the PacFIN catch data to based expansion on
catch.file <- data.frame(googlesheets4::read_sheet(googledrive::drive_get("pacfin_catch"),
                                                   sheet = "catch_mt"))
colnames(catch.file)[1] = c("year")

# Clean up length data
#Remove records with only surface reads (see github issue #11 and pre-assessment workshop presentation)
pacfin[pacfin$FISH_LENGTH_UNITS %in% "UNK", "FISH_LENGTH_UNITS"] = "CM" #these are CMs - need to do first so cleanPacFIN runs

#Give recent CA ages a BB ageing code (otherwise these are removed when cleaning). Recent Oregon ages
#were given an age method of 10, which getAge() doesnt register so set those to 'B'
pacfin[pacfin$AGENCY_CODE=="C" & pacfin$SAMPLE_YEAR>=2010 & !is.na(pacfin$FINAL_FISH_AGE_IN_YEARS), "AGE_METHOD1"] <- "BB"
pacfin[which(pacfin$AGE_METHOD1==10),"AGE_METHOD1"] <- "B"

Pdata = cleanPacFIN(Pdata = pacfin, 
                    CLEAN = TRUE,
                    keep_length_type = c("", "F", "A", "U", NA), #removes the 2 standard length samples
                    keep_sample_type = c("M","S"), #keep ALL special project samples
                    keep_age_method = c("B"),
                    verbose = TRUE)
Pdata <- Pdata[!(Pdata$SAMPLE_TYPE %in% c("S") & Pdata$SAMPLE_YEAR>1986),] #Filter out oregon special project data after 1986

#Convert geargrouping based on fleet structure - HKL, MSC, NET, TLS as "NTWL"; TWL and TWS as "TWL"
table(pacfin$AGENCY_GEAR_CODE,pacfin$PACFIN_GEAR_CODE)
table(Pdata$GEAR,Pdata$geargroup)
fleet <- dplyr::case_when(Pdata$geargroup %in% c("HKL","MSC","NET","TLS") ~ "NTWL",
                                Pdata$geargroup %in% c("TWL","TWS") ~ "TWL")
state <- dplyr::case_when(Pdata$state == "WA" ~ "W",
                          Pdata$state == "OR" ~ "O",
                          Pdata$state == "CA" ~ "C")
Pdata$fleet <- paste(fleet, state, sep = ".")

  #---------------------------------------------------------------------
  #Pull out WDFW aged fish that have multiple reads of B&B to use for ageing error
  #Cleaned data exclude reader info, so join based on SAMPLE_NUMBER and FISH_SEQUENCE_NUMBER
  #from original data and SAMPLE_NO and FISH_NO in cleaned data. These are not unique for CA
  #but are within WA and OR data
  wa_dReads <- Pdata %>% 
    dplyr::filter(state=="WA" & !(is.na(age1) & is.na(age2) & is.na(age3))) %>% 
    dplyr::mutate(mult = dplyr::case_when(
      (!is.na(age1) & !is.na(age2) & !is.na(age3)) == TRUE ~ 3,
      (!is.na(age1) & !is.na(age2)) == TRUE ~ 2,
      (!is.na(age2) & !is.na(age3)) == TRUE ~ 2,
      (!is.na(age1) & !is.na(age3)) == TRUE ~ 2,
      TRUE ~ 1)) %>%
    dplyr::filter(mult > 1 & !(AGE_METHOD1 %in% c("S") & mult == 2)) %>%
    dplyr::left_join(.,pacfin[pacfin$AGENCY_CODE=="W",
                              c("SAMPLE_NUMBER","FISH_SEQUENCE_NUMBER","agedby1","agedby2","agedby3")],
                     by = dplyr::join_by("SAMPLE_NO" == "SAMPLE_NUMBER", "FISH_NO" == "FISH_SEQUENCE_NUMBER"))
  #---------------------------------------------------------------------

#Join agedby to Pdata because cleaned data exclude this. Join based on SAMPLE_NUMBER and 
#FISH_SEQUENCE_NUMBER from original data and SAMPLE_NO and FISH_NO in cleaned data. Does not
#work for CA data.
#2015 assessment used CAPS/ODFW (1), WDFW/ODFW (2), surface (4)
Pdata2 <- Pdata %>%
  dplyr::left_join(.,pacfin[pacfin$AGENCY_CODE%in%c("W","O"),
                            c("SAMPLE_NUMBER","FISH_SEQUENCE_NUMBER","agedby1","agedby2","agedby3")],
                   by = dplyr::join_by("SAMPLE_NO" == "SAMPLE_NUMBER", "FISH_NO" == "FISH_SEQUENCE_NUMBER")) %>%
  dplyr::mutate(lab1 = dplyr::case_when(grepl("ODFW",agedby1) ~ "ODFW",
                        grepl("WDFW",agedby1) ~ "WDFW",
                        grepl("Unknown",agedby1) ~ "NMFS-unk", #assume NMFS, years are 1995-1998 and 2001. Previous model did not have WA there
                        grepl("NMFS",agedby1) ~ "NMFS",
                        is.na(agedby1) & !is.na(FISH_AGE_YEARS_FINAL) ~ "NMFS-na",
                        is.na(agedby1) & is.na(FISH_AGE_YEARS_FINAL) ~ "NA",
                        TRUE ~ "NMFS")) %>% #for betty and patrick
  dplyr::mutate(lab2 = dplyr::case_when(grepl("ODFW",agedby2) ~ "ODFW",
                                        grepl("WDFW",agedby2) ~ "WDFW",
                                        grepl("Unknown",agedby2) ~ "NMFS-unk",
                                        grepl("NMFS",agedby2) ~ "NMFS",
                                        is.na(agedby2) & !is.na(FISH_AGE_YEARS_FINAL) ~ "NMFS-na",
                                        is.na(agedby2) & is.na(FISH_AGE_YEARS_FINAL) ~ "NA",
                                        TRUE ~ "NMFS")) %>% #for betty and patrick
  dplyr::mutate(lab3 = dplyr::case_when(grepl("ODFW",agedby3) ~ "ODFW",
                                        grepl("WDFW",agedby3) ~ "WDFW",
                                        grepl("Unknown",agedby3) ~ "NMFS-unk",
                                        grepl("NMFS",agedby3) ~ "NMFS",
                                        is.na(agedby3) & !is.na(FISH_AGE_YEARS_FINAL) ~ "NMFS-na",
                                        is.na(agedby3) & is.na(FISH_AGE_YEARS_FINAL) ~ "NA",
                                        TRUE ~ "NMFS")) #for betty and patrick

PdataAge = Pdata2 #set up for age comps later
rmNoFin <- which(!is.na(PdataAge$Age) & is.na(PdataAge$FISH_AGE_YEARS_FINAL)) #remove ages without FINAL_AGE assigned (see github issue #11)
PdataAge <- PdataAge[-rmNoFin,]
PdataAge <- PdataAge[!is.na(PdataAge[,"Age"]),]

# PdataAgeCoast <- PdataAge #set up coast age comps for later
# PdataAgeCoast$fleet <- sub("\\..*", "", PdataAgeCoast$fleet) #keep only stuff before "."

Pdata <- Pdata[!is.na(Pdata[, 'length']),] #Remove fish without lengths. Do this here because some of these (12) have ages

# PdataCoast <- Pdata #set up coast length comps for later
# PdataCoast$fleet <- sub("\\..*", "", PdataCoast$fleet) #keep only stuff before "."

table(PdataAge$lab1,PdataAge$lab2,PdataAge$state)
table(PdataAge$lab1,PdataAge$lab3,PdataAge$state)
#in CA -> NMFS
#in OR -> NMFS
table(PdataAge$lab1,PdataAge$lab2, PdataAge$lab3,PdataAge$state=="WA")
#read in WA by lab1 = NMFS or NMFS-unk -> NMFS
#read in WA by lab1=lab2=lab3 = NMFS-na -> NMFS
#read in WA by lab1=NMFS-na but lab2 or lab3 = WDFW -> WDFW
#read in WA by lab1 = ODFW or WDFW -> WDFW with exception of lab1 = ODFW and lab2=lab3 = NMFS-na -> ODFW
#Order below matters
PdataAge <- PdataAge %>% dplyr::mutate(
  ageerr = dplyr::case_when((grepl("-na",lab1) & grepl("WDFW",lab2)) | (grepl("-na",lab1) & grepl("WDFW",lab3)) ~ 2,
                            grepl("NMFS",lab1) ~ 1,
                            grepl("WDFW",lab1) ~ 2,
                            grepl("ODFW",lab1) & grepl("-na",lab2) & grepl("-na",lab3) ~ 1,
                            grepl("ODFW",lab1) ~ 2)) 
table(PdataAge$lab1,PdataAge$lab2,PdataAge$lab3,PdataAge$ageerr)


#################################################################################
# Length and age samples and trips by area and fleet
#################################################################################

trips_sample <- Pdata %>%
  dplyr::group_by(fleet, year) %>%
  dplyr::summarise(
    Trips = length(unique(SAMPLE_NO)),
    Lengths = length(lengthcm)
  )
colnames(trips_sample)[2] <- "Year"
# write.csv(trips_sample, row.names = FALSE, file = file.path(git_dir, "data", "Canary_PacFIN_LengthComps_trips_and_samples.csv"))
#Coast samples we can sum together

# #Put in format for the report
# write.csv(tidyr::pivot_wider(trips_sample,names_from = "fleet", values_from = c("Trips","Lengths"), 
#                              names_sort = TRUE, values_fill = 0) %>%
#             arrange(Year),
#           row.names = FALSE, file = file.path(git_dir,"documents","tables","pacfin_lengths.csv"))


trips_sample <- PdataAge %>%
  dplyr::group_by(fleet, year) %>%
  dplyr::summarise(
    Trips = length(unique(SAMPLE_NO)),
    Ages = length(Age)
  )
colnames(trips_sample)[2] <- "Year"
# write.csv(trips_sample, row.names = FALSE, file = file.path(git_dir, "data", "Canary_PacFIN_AgeComps_trips_and_samples_fixAges.csv"))
#Coast samples we can sum together

# #Put in format for the report
# write.csv(tidyr::pivot_wider(trips_sample,names_from = "fleet", values_from = c("Trips","Ages"),
#                              names_sort = TRUE, values_fill = 0) %>%
#             dplyr::arrange(Year),
#           row.names = FALSE, file = file.path(git_dir,"documents","tables","pacfin_ages_fixAges.csv"))


#################################################################################
# Length comp expansions
#################################################################################

Pdata_exp <- getExpansion_1(Pdata = Pdata,
                            fa = fa, fb = fb, ma = ma, mb = mb, ua = ua, ub = ub)

Pdata_exp <- getExpansion_2(Pdata = Pdata_exp, 
                            Catch = catch.file, 
                            Units = "MT",
                            maxExp = 0.95,
                            stratification.cols = "fleet")

Pdata_exp$Final_Sample_Size <- capValues(Pdata_exp$Expansion_Factor_1_L * Pdata_exp$Expansion_Factor_2, maxVal = 0.80)

# Set up lengths bins based on length sizes for all comps
myLbins = c(seq(12, 66, 2))

Lcomps = getComps(Pdata_exp, Comps = "LEN")

writeComps(inComps = Lcomps, 
           fname = file.path(git_dir, "data", "Canary_PacFIN_LengthComps.csv"), 
           lbins = myLbins, 
           partition = 0, 
           sum1 = TRUE,
           digits = 4)

# ##
# #Coastal expansion
# ##
# PdataCoast_exp <- getExpansion_1(Pdata = PdataCoast,
#                             fa = fa, fb = fb, ma = ma, mb = mb, ua = ua, ub = ub)
# 
# PdataCoast_exp <- getExpansion_2(Pdata = PdataCoast_exp,
#                             Catch = data.frame("year" = catch.file$year,
#                                                "NTWL" = rowSums(catch.file[,c("NTWL.C","NTWL.O","NTWL.W")],na.rm=T),
#                                                "TWL" = rowSums(catch.file[,c("TWL.C","TWL.O","TWL.W")],na.rm=T)),
#                             Units = "MT",
#                             maxExp = 0.95,
#                             stratification.cols = "fleet")
# 
# PdataCoast_exp$Final_Sample_Size <- capValues(PdataCoast_exp$Expansion_Factor_1_L * PdataCoast_exp$Expansion_Factor_2, maxVal = 0.80)
# 
# # Set up lengths bins based on length sizes for all comps
# myLbins = c(seq(12, 66, 2))
# 
# LcompsCoast = getComps(PdataCoast_exp, Comps = "LEN")
# 
# writeComps(inComps = LcompsCoast,
#            fname = file.path(git_dir, "data", "Canary_PacFIN_Coastal_LengthComps.csv"),
#            lbins = myLbins,
#            partition = 0,
#            sum1 = TRUE,
#            digits = 4)


#################################################################################
# Age comp expansions
#################################################################################

Adata_exp <- getExpansion_1(Pdata = PdataAge,
                            fa = fa, fb = fb, ma = ma, mb = mb, ua = ua, ub = ub)

Adata_exp <- getExpansion_2(Pdata = Adata_exp,
                            Catch = catch.file,
                            Units = "MT",
                            maxExp = 0.95,
                            stratification.cols = "fleet")

Adata_exp$Final_Sample_Size <- capValues(Adata_exp$Expansion_Factor_1_A * Adata_exp$Expansion_Factor_2, maxVal = 0.80)

# Set up lengths bins based on length sizes for all comps
myAbins = c(seq(1, 35, 1))

Acomps = getComps(Adata_exp, Comps = "AGE", defaults = c("fleet", "fishyr", "season", "ageerr"))

# loop across ageing error methods to get comps for that method
for(ageerr in unique(Acomps$ageerr)) {
  writeComps(
    inComps = Acomps[Acomps$ageerr == ageerr,],
      fname = file.path(git_dir, "data", paste0("Canary_PacFIN_AgeCompsAgeErr",ageerr,"_fixAges.csv")),
      abins = myAbins,
      partition = 0,
      ageErr = ageerr,
      sum1 = TRUE,
      digits = 4)
  print(paste("ageerr ",ageerr))
}

# ##
# #Coastal expansion - ageerr not applied
# ##
# AdataCoast_exp <- getExpansion_1(Pdata = PdataAgeCoast,
#                             fa = fa, fb = fb, ma = ma, mb = mb, ua = ua, ub = ub)
# 
# AdataCoast_exp <- getExpansion_2(Pdata = AdataCoast_exp,
#                             Catch = data.frame("year" = catch.file$year,
#                                                "NTWL" = rowSums(catch.file[,c("NTWL.C","NTWL.O","NTWL.W")],na.rm=T),
#                                                "TWL" = rowSums(catch.file[,c("TWL.C","TWL.O","TWL.W")],na.rm=T)),
#                             Units = "MT",
#                             maxExp = 0.95,
#                             stratification.cols = "fleet")
# 
# AdataCoast_exp$Final_Sample_Size <- capValues(AdataCoast_exp$Expansion_Factor_1_A * AdataCoast_exp$Expansion_Factor_2, maxVal = 0.80)
# 
# # Set up lengths bins based on length sizes for all comps
# myAbins = c(seq(1, 35, 1))
# 
# AcompsCoast = getComps(AdataCoast_exp, Comps = "AGE")
# 
# writeComps(inComps = AcompsCoast,
#            fname = file.path(git_dir, "data", "Canary_PacFIN_Coastal_AgeComps.csv"),
#            abins = myAbins,
#            partition = 0,
#            sum1 = TRUE,
#            digits = 4)

##############################################################################################################
# Format and rewrite Lengths
##############################################################################################################

#Have to use header = FALSE here because when TRUE I cant read each set of comps, and the variable
#names are fixed as the ones for the combined comps
out = read.csv(file.path(git_dir, "data", "Canary_PacFIN_LengthComps.csv"), skip = 3, header = FALSE)

##
#Extract Unsexed fish
##
start = which(as.character(out[,1]) %in% c(" Usexed only ")) + 2
end   = nrow(out)
cut_out = out[start:end,]
colnames(cut_out) <- out[start-1,]

ind = which(colnames(cut_out) %in% "U12"):which(colnames(cut_out) %in% "U.66") #For 2 sex model need to go to U.66
format = cbind(cut_out$fleet, cut_out$year, cut_out$month, cut_out$fleet, cut_out$sex, cut_out$partition, 
               cut_out$Ntows, cut_out$Nsamps, cut_out$InputN, cut_out[,ind])
colnames(format) = c("state", "fishyr", "month", "fleet", "sex", "part", "Ntows", "Nsamps", "InputN", colnames(cut_out[ind]))

format$state <- sub("^.*\\.","", format$state) #keep only stuff after "."
format$fleet <- sub("\\..*", "", format$fleet) #keep only stuff before "."

ca_comps = format[format$state == "C", ]
or_comps = format[format$state == "O", ]
wa_comps = format[format$state == "W", ]

##
#Extract sexed fish
##
start = 1 + 1
end   = which(as.character(out[,1]) %in% c(" Females only "))
cut_out = out[start:end,]
colnames(cut_out) <- out[1,]

ind = which(colnames(cut_out) %in% "F12"):which(colnames(cut_out) %in% "M66")
format = cbind(cut_out$fleet, cut_out$year, cut_out$month, cut_out$fleet, cut_out$sex, cut_out$partition, 
               cut_out$Ntows, cut_out$Nsamps, cut_out$InputN, cut_out[,ind])
colnames(format) = c("state", "fishyr", "month", "fleet", "sex", "part", "Ntows", "Nsamps", "InputN", colnames(cut_out[ind]))

format$state <- sub("^.*\\.","", format$state) #keep only stuff after "."
format$fleet <- sub("\\..*", "", format$fleet) #keep only stuff before "."

ca_sexed_comps = format[format$state == "C", ]
or_sexed_comps = format[format$state == "O", ]
wa_sexed_comps = format[format$state == "W", ]

#Set up same names so as to combine unsexed and sexed comps
colnames(ca_comps) <- colnames(ca_sexed_comps)
colnames(or_comps) <- colnames(or_sexed_comps)
colnames(wa_comps) <- colnames(wa_sexed_comps)

ca_all_comps = rbind(ca_comps, ca_sexed_comps)
or_all_comps = rbind(or_comps, or_sexed_comps)
wa_all_comps = rbind(wa_comps, wa_sexed_comps)

# write.csv(ca_all_comps, file = file.path(git_dir, "data", "forSS","CA_PacFIN_Lcomps_12_66_formatted.csv"), row.names = FALSE)
# write.csv(or_all_comps, file = file.path(git_dir, "data", "forSS","OR_PacFIN_Lcomps_12_66_formatted.csv"), row.names = FALSE)
# write.csv(wa_all_comps, file = file.path(git_dir, "data", "forSS","WA_PacFIN_Lcomps_12_66_formatted.csv"), row.names = FALSE)


# ##
# #Coastal expansion
# ##
# out = read.csv(file.path(git_dir, "data", "Canary_PacFIN_Coastal_LengthComps.csv"), skip = 3, header = FALSE)
# 
# ##Extract Unsexed fish
# start = which(as.character(out[,1]) %in% c(" Usexed only ")) + 2
# end   = nrow(out)
# cut_out = out[start:end,]
# colnames(cut_out) <- out[start-1,]
# 
# ind = which(colnames(cut_out) %in% "U12"):which(colnames(cut_out) %in% "U.66") #For 2 sex model need to go to U.66
# format = cbind(cut_out$fleet, cut_out$year, cut_out$month, cut_out$fleet, cut_out$sex, cut_out$partition,
#                cut_out$Ntows, cut_out$Nsamps, cut_out$InputN, cut_out[,ind])
# colnames(format) = c("state", "fishyr", "month", "fleet", "sex", "part", "Ntows", "Nsamps", "InputN", colnames(cut_out[ind]))
# 
# format$state <- "coastal"
# 
# ##Extract sexed fish
# start = 1 + 1
# end   = which(as.character(out[,1]) %in% c(" Females only "))
# cut_out = out[start:end,]
# colnames(cut_out) <- out[1,]
# 
# ind = which(colnames(cut_out) %in% "F12"):which(colnames(cut_out) %in% "M66")
# format_coastal = cbind(cut_out$fleet, cut_out$year, cut_out$month, cut_out$fleet, cut_out$sex, cut_out$partition,
#                cut_out$Ntows, cut_out$Nsamps, cut_out$InputN, cut_out[,ind])
# colnames(format_coastal) = c("state", "fishyr", "month", "fleet", "sex", "part", "Ntows", "Nsamps", "InputN", colnames(cut_out[ind]))
# 
# format_coastal$state <- "coastal"
# 
# #Set up same names so as to combine unsexed and sexed comps
# colnames(format) <- colnames(format_coastal)
# 
# coastal_all_comps = rbind(format, format_coastal)
# 
# # write.csv(coastal_all_comps, file = file.path(git_dir, "data", "forSS","Coastal_PacFIN_Lcomps_12_66_formatted.csv"), row.names = FALSE)


##############################################################################################################
# Format and rewrite Ages
##############################################################################################################

#Have to use header = FALSE here because when TRUE I cant read each set of comps, and the variable
#names are fixed as the ones for the combined comps
ca_all_comps = or_all_comps = wa_all_comps = NULL

for(i in unique(Acomps$ageerr)){
  out = read.csv(file.path(git_dir, "data", paste0("Canary_PacFIN_AgeCompsAgeErr",i,"_fixAges.csv")), skip = 3, header = FALSE)
  
  ##
  #Extract Unsexed fish
  ##
  start = which(as.character(out[,1]) %in% c(" Usexed only ")) + 2
  end   = nrow(out)
  cut_out = out[start:end,]
  colnames(cut_out) <- out[start-1,]
  
  ind = which(colnames(cut_out) %in% "U1"):which(colnames(cut_out) %in% "U.35") #For 2 sex model need to go to U.66
  format = cbind(cut_out$fleet, cut_out$year, cut_out$month, cut_out$fleet, cut_out$sex, cut_out$partition,
                 cut_out$ageErr, cut_out$LbinLo, cut_out$LbinHi,
                 cut_out$Ntows, cut_out$Nsamps, cut_out$InputN, cut_out[,ind])
  colnames(format) = c("state", "fishyr", "month", "fleet", "sex", "part", "ageerr", "Lbin_lo", "Lbin_hi", "Ntows", "Nsamps", "InputN", colnames(cut_out[ind]))
  
  format$state <- sub("^.*\\.","", format$state) #keep only stuff after "."
  format$fleet <- sub("\\..*", "", format$fleet) #keep only stuff before "."
  
  ca_comps = format[format$state == "C", ]
  or_comps = format[format$state == "O", ]
  wa_comps = format[format$state == "W", ]
  
  ##
  #Extract sexed fish
  ##
  start = 1 + 1
  end   = which(as.character(out[,1]) %in% c(" Females only "))
  cut_out = out[start:end,]
  colnames(cut_out) <- out[1,]
  
  ind = which(colnames(cut_out) %in% "F1"):which(colnames(cut_out) %in% "M35")
  format = cbind(cut_out$fleet, cut_out$year, cut_out$month, cut_out$fleet, cut_out$sex, cut_out$partition,
                 cut_out$ageErr, cut_out$LbinLo, cut_out$LbinHi,
                 cut_out$Ntows, cut_out$Nsamps, cut_out$InputN, cut_out[,ind])
  colnames(format) = c("state", "fishyr", "month", "fleet", "sex", "part", "ageerr", "Lbin_lo", "Lbin_hi", "Ntows", "Nsamps", "InputN", colnames(cut_out[ind]))
  
  format$state <- sub("^.*\\.","", format$state) #keep only stuff after "."
  format$fleet <- sub("\\..*", "", format$fleet) #keep only stuff before "."
  
  ca_sexed_comps = format[format$state == "C", ]
  or_sexed_comps = format[format$state == "O", ]
  wa_sexed_comps = format[format$state == "W", ]
  
  #Set up same names so as to combine unsexed and sexed comps
  colnames(ca_comps) <- colnames(ca_sexed_comps)
  colnames(or_comps) <- colnames(or_sexed_comps)
  colnames(wa_comps) <- colnames(wa_sexed_comps)
  
  ca_all_comps = rbind(ca_all_comps, ca_comps, ca_sexed_comps)
  or_all_comps = rbind(or_all_comps, or_comps, or_sexed_comps)
  wa_all_comps = rbind(wa_all_comps, wa_comps, wa_sexed_comps)
}

# write.csv(ca_all_comps, file = file.path(git_dir, "data", "forSS","CA_PacFIN_Acomps_1_35_formatted_fixAges.csv"), row.names = FALSE)
# write.csv(or_all_comps, file = file.path(git_dir, "data", "forSS","OR_PacFIN_Acomps_1_35_formatted_fixAges.csv"), row.names = FALSE)
# write.csv(wa_all_comps, file = file.path(git_dir, "data", "forSS","WA_PacFIN_Acomps_1_35_formatted_fixAges.csv"), row.names = FALSE)


# ##
# #Coastal expansion - ageerr values aren't updated here
# ##
# out = read.csv(file.path(git_dir, "data", "Canary_PacFIN_Coastal_AgeComps.csv"), skip = 3, header = FALSE)
# 
# ##Extract Unsexed fish
# start = which(as.character(out[,1]) %in% c(" Usexed only ")) + 2
# end   = nrow(out)
# cut_out = out[start:end,]
# colnames(cut_out) <- out[start-1,]
# 
# ind = which(colnames(cut_out) %in% "U1"):which(colnames(cut_out) %in% "U.35") #For 2 sex model need to go to U.66
# format = cbind(cut_out$fleet, cut_out$year, cut_out$month, cut_out$fleet, cut_out$sex, cut_out$partition,
#                cut_out$ageErr, cut_out$LbinLo, cut_out$LbinHi,
#                cut_out$Ntows, cut_out$Nsamps, cut_out$InputN, cut_out[,ind])
# colnames(format) = c("state", "fishyr", "month", "fleet", "sex", "part", "ageerr", "Lbin_lo", "Lbin_hi", "Ntows", "Nsamps", "InputN", colnames(cut_out[ind]))
# 
# format$state <- "coastal"
# 
# ##Extract sexed fish
# start = 1 + 1
# end   = which(as.character(out[,1]) %in% c(" Females only "))
# cut_out = out[start:end,]
# colnames(cut_out) <- out[1,]
# 
# ind = which(colnames(cut_out) %in% "F1"):which(colnames(cut_out) %in% "M35")
# format_coastal = cbind(cut_out$fleet, cut_out$year, cut_out$month, cut_out$fleet, cut_out$sex, cut_out$partition,
#                cut_out$ageErr, cut_out$LbinLo, cut_out$LbinHi,
#                cut_out$Ntows, cut_out$Nsamps, cut_out$InputN, cut_out[,ind])
# colnames(format_coastal) = c("state", "fishyr", "month", "fleet", "sex", "part", "ageerr", "Lbin_lo", "Lbin_hi", "Ntows", "Nsamps", "InputN", colnames(cut_out[ind]))
# 
# format_coastal$state <- "coastal"
# 
# #Set up same names so as to combine unsexed and sexed comps
# colnames(format) <- colnames(format_coastal)
# 
# coastal_all_comps = rbind(format, format_coastal)
# 
# # write.csv(coastal_all_comps, file = file.path(git_dir, "data", "forSS","Coastal_PacFIN_Acomps_1_35_formatted.csv"), row.names = FALSE)


##############################################################################################################
# Plot the comps
##############################################################################################################

