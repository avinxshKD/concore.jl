using Documenter
using Concore

makedocs(;
    modules=[Concore],
    authors="Avinash Kumar Deepak",
    repo="https://github.com/avinxshKD/concore.jl",
    sitename="Concore.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://controlcore-project.github.io/concore/julia/",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "Getting Started" => "guide.md",
        "API Reference" => "api.md",
        "Backends" => "backends.md",
        "Cross-Language Interop" => "interop.md",
        "Contributing" => "contributing.md",
    ],
)

deploydocs(;
    repo="github.com/avinxshKD/concore.jl",
    devbranch="main",
)
