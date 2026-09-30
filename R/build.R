## BUILD ##

# Rebuilds everything the app needs, from the project root:
#   source("R/build.R")
# 1. data prep -> app/data.RData
# 2. analysis report -> analysis.html -> app/www/analysis.html

source("R/prep_data.R")

status <- system2("quarto", c("render", "analysis.qmd"))
stopifnot("Quarto render failed" = status == 0)
file.copy("analysis.html", "app/www/analysis.html", overwrite = TRUE)

message("Build complete. Run the app with shiny::runApp('app').")
