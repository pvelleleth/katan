require "./types"

enum DevCard
  Knight
  VictoryPoint
  RoadBuilding
  YearOfPlenty
  Monopoly
end

class DevCardHand
  property knight : Int32
  property victory_point : Int32
  property road_building : Int32
  property year_of_plenty : Int32
  property monopoly : Int32

  def initialize(@knight = 0, @victory_point = 0, @road_building = 0, @year_of_plenty = 0, @monopoly = 0)
  end

  def add(card : DevCard, amount : Int32 = 1) : Nil
    case card
    when .knight?         then @knight += amount
    when .victory_point?  then @victory_point += amount
    when .road_building?  then @road_building += amount
    when .year_of_plenty? then @year_of_plenty += amount
    when .monopoly?       then @monopoly += amount
    end
  end

  def remove(card : DevCard, amount : Int32 = 1) : Nil
    raise "insufficient #{card} development cards" unless count(card) >= amount
    add(card, -amount)
  end

  def count(card : DevCard) : Int32
    case card
    when .knight?         then @knight
    when .victory_point?  then @victory_point
    when .road_building?  then @road_building
    when .year_of_plenty? then @year_of_plenty
    when .monopoly?       then @monopoly
    else
      0
    end
  end

  def total : Int32
    @knight + @victory_point + @road_building + @year_of_plenty + @monopoly
  end

  def merge!(other : DevCardHand) : Nil
    @knight += other.knight
    @victory_point += other.victory_point
    @road_building += other.road_building
    @year_of_plenty += other.year_of_plenty
    @monopoly += other.monopoly
    other.clear!
  end

  def clear! : Nil
    @knight = 0
    @victory_point = 0
    @road_building = 0
    @year_of_plenty = 0
    @monopoly = 0
  end

  def to_json_payload
    {
      knight:         @knight,
      victory_point:  @victory_point,
      road_building:  @road_building,
      year_of_plenty: @year_of_plenty,
      monopoly:       @monopoly,
      total:          total,
    }
  end
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

  def withdraw_dev_card!(card : DevCard, amount : Int32 = 1) : Nil
    case card
    when .knight?
      raise "insufficient #{card} development cards" unless @knight >= amount
      @knight -= amount
    when .victory_point?
      raise "insufficient #{card} development cards" unless @victory_point >= amount
      @victory_point -= amount
    when .road_building?
      raise "insufficient #{card} development cards" unless @road_building >= amount
      @road_building -= amount
    when .year_of_plenty?
      raise "insufficient #{card} development cards" unless @year_of_plenty >= amount
      @year_of_plenty -= amount
    when .monopoly?
      raise "insufficient #{card} development cards" unless @monopoly >= amount
      @monopoly -= amount
    end
  end

  def deposit_dev_card!(card : DevCard, amount : Int32 = 1) : Nil
    case card
    when .knight?         then @knight += amount
    when .victory_point?  then @victory_point += amount
    when .road_building?  then @road_building += amount
    when .year_of_plenty? then @year_of_plenty += amount
    when .monopoly?       then @monopoly += amount
    end
  end

  def sample_dev_card(rng : Random) : DevCard
    remaining = dev_cards_remaining
    raise "no development cards remaining" if remaining.zero?

    roll = rng.rand(remaining)
    cumulative = 0

    DEV_CARD_COUNTS.keys.each do |card|
      cumulative += count(card)
      next unless roll < cumulative

      return card
    end

    raise "failed to draw development card"
  end

  def draw_dev_card!(rng : Random) : DevCard
    card = sample_dev_card(rng)
    withdraw_dev_card!(card)
    card
  end

  def count(card : DevCard) : Int32
    case card
    when .knight?         then @knight
    when .victory_point?  then @victory_point
    when .road_building?  then @road_building
    when .year_of_plenty? then @year_of_plenty
    when .monopoly?       then @monopoly
    else
      0
    end
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
