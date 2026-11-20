using Documenter
using BrewQuiverUICore, BrewQuiver, Unitful, UnitfulBrewing, BrewingFormulas

DocMeta.setdocmeta!(BrewQuiverUICore, :DocTestSetup,
                    :(using BrewQuiverUICore, BrewQuiver, Unitful, UnitfulBrewing); recursive = true)

makedocs(;
    modules = [BrewQuiverUICore],
    sitename = "BrewQuiverUICore.jl",
    authors = "JuliaBrewing contributors",
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://juliabrewing.github.io/BrewQuiverUICore.jl",
        edit_link = "main",
        size_threshold_warn = 200 * 1024,
    ),
    pages = [
        "Home" => "index.md",
        "Concepts" => "concepts.md",
        "Guide" => [
            "Editing, undo and redo" => "guide/editing.md",
            "View data and layout" => "guide/views.md",
            "Writing a frontend" => "guide/frontends.md",
            "New commands" => "guide/extending.md",
        ],
        "API reference" => "api.md",
    ],
    checkdocs = :exports,
)

deploydocs(;
    repo = "github.com/JuliaBrewing/BrewQuiverUICore.jl.git",
    devbranch = "main",
    push_preview = true,
)
