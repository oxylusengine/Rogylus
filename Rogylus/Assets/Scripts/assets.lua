Assets = {
  player_model_asset = {},
  enemy_model_asset = {},
  weapon_model_asset = {},
  projectile_model_asset = {},
}

function Assets.load_assets(WORKING_DIR)
  local asset_man = App:get_asset_manager()
  local vfs = App:get_vfs();

  local models_dir = vfs:resolve_physical_dir(WORKING_DIR, "Models")

  Assets.enemy_model_asset = asset_man:import_asset(models_dir .. "/enemy.glb.oxasset")
  Assets.player_model_asset = asset_man:import_asset(models_dir .. "/player.glb.oxasset")
  Assets.weapon_model_asset = asset_man:import_asset(models_dir .. "/weapon.glb.oxasset")
  Assets.projectile_model_asset = asset_man:import_asset(models_dir .. "/projectile.glb.oxasset")
  asset_man:load_asset(Assets.projectile_model_asset) -- pre load projectile model
end

return Assets
