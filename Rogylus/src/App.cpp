#include <Core/App.hpp>
#include <Core/DefaultModules.hpp>
#include <Core/Enum.hpp>

#include "Game.hpp"

int main(int argc, char** argv) {
  auto app = ox::App(argc, argv);
  app.with_name("Rogylus")
    .with_window({
      .title = "Rogylus",
      .icon = {},
      .width = 1600,
      .height = 900,
      .flags = ox::WindowFlag::Centered | ox::WindowFlag::HighPixelDensity | ox::WindowFlag::Resizable,
    })
    .with_assets_directory("Assets")
    .with(ox::DefaultModules{})
    .with<rogylus::Game>()
    .run();

  return 0;
}
