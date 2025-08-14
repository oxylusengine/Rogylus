target("Rogylus")
    set_kind("binary")
    set_languages("cxx23")

    add_includedirs("./src")
    add_files("./src/**.cpp")

    if has_config("local_dev") then
        add_deps("Oxylus")
    else
        add_packages("oxylus")
    end

    add_files("./Assets/**")
    if has_config("local_dev") then 
        add_rules("ox.install_resources", {
            root_dir = os.scriptdir() .. "/Assets",
            output_dir = "Assets",
        })

        add_files("../../Oxylus/Oxylus/src/Render/Shaders/**")
        add_rules("ox.install_shaders", {
            output_dir = "Assets/Shaders",
        })
    else
        add_rules("@oxylus/install_resources", {
            root_dir = os.scriptdir() .. "/Resources",
            output_dir = "Resources",
        })
        add_rules("@oxylus/install_shaders", {
            output_dir = "Resources/Shaders",
        })
    end

target_end()
