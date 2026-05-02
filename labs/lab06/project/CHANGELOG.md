**Changelog**  
All notable changes to this project will be documented in this file.  
**[6.0.0] - 2026-05-02**  
**Added**  
- SIR Petri net module (src/SIRPetri.jl) with deterministic and stochastic simulation  
- Base simulation script (scripts/sirpetri_run.jl)  
- Parameter scanning script for infection rate β (scripts/sirpetri_scan_parameters.jl)  
- Animation script for SIR dynamics (scripts/sirpetri_animate.jl)  
- Report script for comparative plots (scripts/sirpetri_report.jl)  
- Complete lab report in Quarto format (Л06_Черная_отчет.qmd)  
- Presentation slides in Quarto format (Л06_Черная_презентация.qmd)  
- All screenshots (1-21, comparison, sensitivity)  
**Changed**  
- Nothing yet  
**Fixed**  
- Fixed GKS graphics issues on headless systems (added ENV["GKSwstype"] = "nul")  
- Added missing using DataFrames import in animation script  
**Dependencies**  
- AlgebraicPetri.jl v0.10.0  
- Catlab.jl v0.17.5  
- DrWatson.jl  
- OrdinaryDiffEq.jl  
- Plots.jl  
