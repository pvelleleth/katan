require "./types"

enum DevCard
  Knight
  VictoryPoint
  RoadBuilding
  YearOfPlenty
  Monopoly
end

# Standard Catan: 19 of each resource, 25 dev cards (14 Knight, 5 VP, 2 Road Building, 2 Year of Plenty, 2 Monopoly)
RESOURCE_SUPPLY = 19
DEV_CARD_COUNTS = {
  DevCard::Knight         => 14,
  DevCard::VictoryPoint   => 5,
  DevCard::RoadBuilding   => 2,
  DevCard::YearOfPlenty   => 2,
  DevCard::Monopoly       => 2,
}

# The game's central resource and dev card supply. One per game.
class Bank
  getter resources : ResourcePile
  getter knight : Int32
  getter victory_point : Int32
  getter road_building : Int32
  getter year_of_plenty : Int32
  getter monopoly : Int32

  def initialize(
    resources : ResourcePile? = nil,
    @knight = DEV_CARD_COUNTS[DevCard::Knight],
    @victory_point = DEV_CARD_COUNTS[DevCard::VictoryPoint],
    @road_building = DEV_CARD_COUNTS[DevCard::RoadBuilding],
    @year_of_plenty = DEV_CARD_COUNTS[DevCard::YearOfPlenty],
    @monopoly = DEV_CARD_COUNTS[DevCard::Monopoly]
  )
    @resources = resources || ResourcePile.new(
      RESOURCE_SUPPLY, RESOURCE_SUPPLY, RESOURCE_SUPPLY, RESOURCE_SUPPLY, RESOURCE_SUPPLY
    )
  end

  def dev_cards_remaining : Int32
    @knight + @victory_point + @road_building + @year_of_plenty + @monopoly
  end

  def withdraw!(resource : Resource, amount : Int32 = 1) : Nil
    @resources.remove(resource, amount)
  end

  def deposit!(resource : Resource, amount : Int32 = 1) : Nil
    @resources.add(resource, amount)
  end

  def to_json_payload
    {
      resources: {
        wood:   @resources.wood,
        brick:  @resources.brick,
        sheep:  @resources.sheep,
        wheat:  @resources.wheat,
        ore:    @resources.ore,
      },
      dev_cards: {
        knight:         @knight,
        victory_point:  @victory_point,
        road_building:  @road_building,
        year_of_plenty: @year_of_plenty,
        monopoly:       @monopoly,
      },
    }
  end
end
