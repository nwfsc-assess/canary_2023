library(r4ss)
library(here)
library(dplyr)

if(Sys.getenv("USERNAME") == "Brian.Langseth") {
  wd = "L:/"
}
if(Sys.getenv("USERNAME") == "Kiva.Oken") {
  wd = "Q:/"
}

source(here('code/table_decision.R'))

#Set up low and high states of nature
low_state <- "sensitivities/STAR_single_M"
high_state <- "sensitivities/STAR_M_ramp"

#####-------------------------------------------####
#Run alternative states of nature for Pstar = 0.45 which we have already run for the base
#####-------------------------------------------####

pstar <- 0.45
base45 <- "7_3_5_reweight"

#Get new forecast catches
base_mod <- SS_output(here('models',base45))
fore_catch <- r4ss::SS_ForeCatch(base_mod, yrs = 2023:2034)


##
#Set up low state first
##
mod <- SS_read(here('models',low_state))
mod$fore$ForeCatch <- fore_catch

#Turn off buffers
mod$fore$Flimitfraction <- 1 #dont have years of buffer applied
mod$fore$FirstYear_for_caps_and_allocations <- 2035 #these should be overwritten with the fixed catch but putting here anyway

#Estimate from par file parameters
mod$start$init_values_src <-1

SS_write(mod,
         dir = here('models','decision_tables',paste0("low_",pstar)),
         overwrite = TRUE)

r4ss::run(dir = here('models','decision_tables',paste0("low_",pstar)),
          exe = here('models/ss_win.exe'),
          extras = '-nohess',
          # show_in_console = TRUE,
          skipfinished = FALSE)


##
#Now set up high state
##
mod <- SS_read(here('models',high))
mod$fore$ForeCatch <- fore_catch

#Turn off buffers
mod$fore$Flimitfraction <- 1 #dont have years of buffer applied
mod$fore$FirstYear_for_caps_and_allocations <- 2035 #these should be overwritten with the fixed catch but putting here anyway

#Estimate from par file parameters
mod$start$init_values_src <-1

SS_write(mod,
         dir = here('models','decision_tables',paste0("high_",pstar)),
         overwrite = TRUE)

r4ss::run(dir = here('models','decision_tables',paste0("high_",pstar)),
          exe = here('models/ss_win.exe'),
          extras = '-nohess',
          # show_in_console = TRUE,
          skipfinished = FALSE)


#####-------------------------------------------####
#Pstar = 0.40
#####-------------------------------------------####

pstar <- 0.40

#Set up base model with new pstar
mod <- SS_read(here('models',base45))
mod$fore$Flimitfraction_m <- data.frame("Year" = 2023:2034, 
                                        "Fraction" = get_buffer(c(2023:2034), sigma = 0.5, pstar = pstar)[,2])
SS_write(mod,
         dir = here('models','decision_tables',paste0("base_",pstar)),
         overwrite = TRUE)

r4ss::run(dir = here('models','decision_tables',paste0("base_",pstar)),
          exe = here('models/ss_win.exe'),
          extras = '-nohess',
          # show_in_console = TRUE,
          skipfinished = FALSE)

#Get new forecast catches
base_mod <- SS_output(here('models','decision_tables',paste0("base_",pstar)))
fore_catch <- r4ss::SS_ForeCatch(base_mod, yrs = 2023:2034)


##
#Set up low state first
##
mod <- SS_read(here('models',low_state))
mod$fore$ForeCatch <- fore_catch

#Turn off buffers
mod$fore$Flimitfraction <- 1 #dont have years of buffer applied
mod$fore$FirstYear_for_caps_and_allocations <- 2035 #these should be overwritten with the fixed catch but putting here anyway

#Estimate from par file parameters
mod$start$init_values_src <-1

SS_write(mod,
         dir = here('models','decision_tables',paste0("low_",pstar)),
         overwrite = TRUE)

r4ss::run(dir = here('models','decision_tables',paste0("low_",pstar)),
          exe = here('models/ss_win.exe'),
          extras = '-nohess',
          # show_in_console = TRUE,
          skipfinished = FALSE)


##
#Now set up high state
##
mod <- SS_read(here('models',high))
mod$fore$ForeCatch <- fore_catch

#Turn off buffers
mod$fore$Flimitfraction <- 1 #dont have years of buffer applied
mod$fore$FirstYear_for_caps_and_allocations <- 2035 #these should be overwritten with the fixed catch but putting here anyway

#Estimate from par file parameters
mod$start$init_values_src <-1

SS_write(mod,
         dir = here('models','decision_tables',paste0("high_",pstar)),
         overwrite = TRUE)

r4ss::run(dir = here('models','decision_tables',paste0("high_",pstar)),
          exe = here('models/ss_win.exe'),
          extras = '-nohess',
          # show_in_console = TRUE,
          skipfinished = FALSE)



#####-------------------------------------------####
#Decision Table
#####-------------------------------------------####

low45 <- SS_output(here('models','decision_tables',"low_0.45"))
base45 <- SS_output(here('models',"7_3_5_reweight"))
high45 <- SS_output(here('models','decision_tables',"high_0.45"))

low40 <- SS_output(here('models','decision_tables',"low_0.4"))
base40 <- SS_output(here('models','decision_tables',"base_0.4"))
high40 <- SS_output(here('models','decision_tables',"high_0.4"))


caption <- "Decision table with 10-year projections beginning in 2025 for alternative states of nature based around 
modeling natural mortality. 'Mgmt' refers to the two management scenarios (A) the default harvest control rule 
$P^* = 0.45$, and (B) harvest control rule with a lower $P^* = 0.40$. Catch (in mt) is from the projections from the 
base model for each management scenario, and is applied to each state of nature. Catches in 2023 
and 2024 are fixed at the ACLs and have been set for that year with values provided by the GMT. The alternative 
states of nature ('Low', 'Base', and 'High') are provided in the columns, and assume female natural mortality is either 
fixed at the prior estimate (Single M; low state), estimated as age-invariant (base), or is estimated at older ages
(M ramp; high state). Spawning output ('Spawn', in millions of eggs) and fraction of unfished ('Frac') is provided for each state of nature."

tab <- table_decision(
  caption = caption,
  label = "es-decision",
  list(low45, base45, high45),
  list(low40, base40, high40)
)
writeLines(tab,here('documents',"tables", "decision_table_es.tex"))

tab <- table_decision(
  caption = caption,
  label = "dec-tab",
  list(low45, base45, high45),
  list(low40, base40, high40)
)
writeLines(tab,here('documents',"tables", "decision_table.tex"))


#####-------------------------------------------####
#Run STAR panel request 15 of a projected base but with average recruitment from a time with lower recdevs
#####-------------------------------------------####

pstar <- 0.45
base45 <- "7_3_5_reweight"

#Set up base model with new recruitment period
mod <- SS_read(here('models',base45))
mod$fore$Fcast_years[c(5,6)] <- c(2014,2019)
mod$fore$fcast_rec_option <- 3 #Turn on average recruitment option

#Use catch from original base model with recruits from SR curve
mod$fore$ForeCatch <- fore_catch

#Turn off buffers
mod$fore$Flimitfraction <- 1 #dont have years of buffer applied
mod$fore$FirstYear_for_caps_and_allocations <- 2035 #these should be overwritten with the fixed catch but putting here anyway

#I dont think we need to read from the par file but could

SS_write(mod,
         dir = here('models','decision_tables', paste0("base_",pstar,"_lowRecruit")),
         overwrite = TRUE)

r4ss::run(dir = here('models','decision_tables', paste0("base_",pstar,"_lowRecruit")),
          exe = here('models/ss_win.exe'),
          extras = '-nohess',
          # show_in_console = TRUE,
          skipfinished = FALSE)


xx <- SSgetoutput(dirvec = glue::glue("{models}/{subdir}", models = here('models'),
                                      subdir = c('7_3_5_reweight',
                                                 'decision_tables/base_0.45_lowRecruit')))
SSsummarize(xx) |>
  SSplotComparisons(legendlabels = c('base model',
                                     'average recruit from 2014-2019'), 
                    endyrvec = 2034, shadeForecast = TRUE, btarg = 0, minbthresh = 0,
                    subplot = c(2,4,9,11), print = TRUE, plotdir = here('models','decision_tables', paste0("base_",pstar,"_lowRecruit")))

file.copy(from =  here('models','decision_tables', paste0("base_",pstar,"_lowRecruit"),'compare4_Bratio_uncertainty.png'),
          to = here('documents','figures',
                    c("compare_lowrecruit_projection_Bratio.png")), overwrite = TRUE)


#####-------------------------------------------####
#If wanted to set up a regime block for recruits
#####-------------------------------------------####

pstar <- 0.45
base45 <- "7_3_5_reweight"

#Set up base model with recruitment regime period
mod <- SS_read(here('models',base45))
mod$ctl$N_Block_Designs <- 7
mod$ctl$blocks_per_pattern[7] <- 1
names(mod$ctl$blocks_per_pattern) <- paste0("blocks_per_pattern_",1:mod$ctl$N_Block_Designs)
mod$ctl$Block_Design[[7]] <- c(2023, 2034)

#Set up regime (SR time varying parameter)
mod$ctl$SR_parms["SR_regime",c("Block","Block_Fxn")] <- c(7,1)
mod$ctl$SR_parms_tv <- data.frame('LO' = -5, 'HI' = 5, 'INIT' = 0, 'PRIOR' = 0, 'PR_SD' = 0, 'PR_type' = 0, 'PHASE' = -50)

#Set the value for the regime change (2014-2019). 
#Take the exp of the devs, average them, and then take the log as the initial (fixed) value for the regime change
pp <- SS_output(here('models',base45))
mod$ctl$SR_parms_tv$INIT = log(mean(exp(pp$recruit$dev[pp$recruit$Yr %in% c(2014:2019)])))

#Use catch from original base model with recruits from SR curve
mod$fore$ForeCatch <- fore_catch

#Turn off buffers
mod$fore$Flimitfraction <- 1 #dont have years of buffer applied
mod$fore$FirstYear_for_caps_and_allocations <- 2035 #these should be overwritten with the fixed catch but putting here anyway

#I dont think we need to read from the par file but could

SS_write(mod,
         dir = here('models','decision_tables', paste0("base_",pstar,"_lowRecruit_regimeBlockAuto")),
         overwrite = TRUE)

r4ss::run(dir = here('models','decision_tables', paste0("base_",pstar,"_lowRecruit")),
          exe = here('models/ss_win.exe'),
          extras = '-nohess',
          # show_in_console = TRUE,
          skipfinished = FALSE)


xx <- SSgetoutput(dirvec = glue::glue("{models}/{subdir}", models = here('models'),
                                      subdir = c('7_3_5_reweight',
                                                 'decision_tables/base_0.45_lowRecruit',
                                                 'decision_tables/base_0.45_lowRecruit_regimeBlockAuto')))
SSsummarize(xx) |>
  SSplotComparisons(legendlabels = c('base model',
                                     'average recruit from 2014-2019',
                                     'regime block'), 
                    endyrvec = 2034, shadeForecast = TRUE, btarg = 0, minbthresh = 0,
                    subplot = c(2,4,9,11), print = TRUE, plotdir = here('models','decision_tables', paste0("base_",pstar,"_lowRecruit_regimeBlockAuto")))








