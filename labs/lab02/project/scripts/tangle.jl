#!/usr/bin/env julia
# tangle.jl
using DrWatson
@quickactivate
using Literate

function main()
    if length(ARGS) == 0
        println("Использование: julia tangle.jl <путь_к_скрипту>")
        return
    end
    script_path = ARGS[1]
    script_name = splitext(basename(script_path))[1]
    
    # Чистый скрипт
    scripts_dir = scriptsdir(script_name)
    Literate.script(script_path, scripts_dir; credit=false)
    
    # Quarto
    quarto_dir = projectdir("markdown", script_name)
    Literate.markdown(script_path, quarto_dir; flavor=Literate.QuartoFlavor(), name=script_name, credit=false)
    
    # Jupyter Notebook (execute=true для выполнения кода)
    notebooks_dir = projectdir("notebooks", script_name)
    Literate.notebook(script_path, notebooks_dir, name=script_name; execute=false, credit=false)
    
    println("✅ Файлы для $script_name сгенерированы.")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

