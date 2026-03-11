using Documenter
using Concore

makedocs(;
    modules=[Concore],
    authors="Avinash Kumar Deepak",
    sitename="Concore.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        edit_link="main",
        assets=String[],
    ),
    remotes=nothing,
    warnonly=true,
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
