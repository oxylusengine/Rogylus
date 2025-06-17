add_repositories("oxylus https://github.com/oxylusengine/xmake-repo.git")
target("Rogylus")
    set_kind("binary")
    set_languages("cxx23")

    add_includedirs("./src")
    add_files("./src/**.cpp")

    add_files("./Assets/**")
    add_rules("ox.install_resources", {
        root_dir = os.scriptdir() .. "/Assets",
        output_dir = "Assets",
    })

target_end()