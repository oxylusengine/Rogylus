#pragma once
#include <Core/Layer.hpp>
#include <Scene/Scene.hpp>

namespace rog {
class RogylusLayer : public ox::Layer {
public:
  RogylusLayer();
  ~RogylusLayer() override = default;
  void on_attach() override;
  void on_detach() override;
  void on_update(const ox::Timestep& delta_time) override;
  void on_render(vuk::Extent3D extent, vuk::Format format) override;

  static RogylusLayer* get() { return _instance; }

private:
  std::shared_ptr<ox::Scene> _scene = nullptr;
  static RogylusLayer* _instance;
};
} // namespace rog
