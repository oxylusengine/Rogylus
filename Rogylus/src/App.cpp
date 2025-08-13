#include <Core/EntryPoint.hpp>
#include <Core/App.hpp>

#include "RogylusLayer.hpp"

#include <filesystem>

namespace ox {
class RogylusApp : public ox::App {
public:
  RogylusApp(const ox::AppSpec& spec) : App(spec) { }
};

App* create_application(const AppCommandLineArgs& args) {
  AppSpec spec;
  spec.name = "Rogylus";
  spec.working_directory = std::filesystem::current_path().string();
  spec.command_line_args = args;
  spec.assets_path = "Resources";
  spec.headless = false;
  const WindowInfo::Icon icon = { };
  spec.window_info = {
	  .title = spec.name,
	  .icon = icon,
	  .width = 1720,
	  .height = 900,
#ifdef OX_PLATFORM_LINUX
	  .flags = WindowFlag::Centered,
#else
	  .flags = WindowFlag::Centered | WindowFlag::Resizable,
#endif
  };

  const auto app = new RogylusApp(spec);
  app->push_layer(std::make_unique<rog::RogylusLayer>());

  return app;
}
}