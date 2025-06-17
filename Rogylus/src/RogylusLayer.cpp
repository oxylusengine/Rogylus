#include "RogylusLayer.hpp"

namespace rog {
RogylusLayer* RogylusLayer::_instance = nullptr;

RogylusLayer::RogylusLayer() : Layer("Game Layer") { _instance = this; }

void RogylusLayer::on_attach() { }

void RogylusLayer::on_detach() { }

void RogylusLayer::on_update(const ox::Timestep& delta_time) { }

void RogylusLayer::on_render(vuk::Extent3D extent, vuk::Format format) { }
} // namespace rog
