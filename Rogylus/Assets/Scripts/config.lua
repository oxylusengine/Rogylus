local Config = {
  -- XP curve settings
  BaseXP = 100,       -- XP required for level 2
  XPMultiplier = 1.5, -- How much more XP each level needs
  XPAdditive = 50,    -- Flat amount added per level

  -- Enemy scaling
  BaseEnemyXP = 10,      -- Base XP an enemy gives
  EnemyXPScaling = 1.2,  -- XP scaling per player level
  BaseEnemyGold = 5,     -- Base gold an enemy gives
  EnemyGoldScaling = 1.1, -- Gold scaling per player level

  -- Enemy spawn scaling
  BaseEnemiesPerRoom = 3,
  EnemyCountScaling = 1.1, -- How much enemy count increases per level
  MaxEnemiesPerRoom = 15,

  -- Elite/Boss multipliers
  EliteXpMultiplier = 2.5,
  BossXPMultiplier = 5.0,

  RarityWeights = {
    common = 60,
    uncommon = 25,
    rare = 12,
    legendary = 3
  }
}

return Config;