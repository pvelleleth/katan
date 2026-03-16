enum Resource
  Wood
  Brick
  Sheep
  Wheat
  Ore
  Desert
end

struct ResourcePile
  property wood : Int32
  property brick : Int32
  property sheep : Int32
  property wheat : Int32
  property ore : Int32

  def initialize(@wood = 0, @brick = 0, @sheep = 0, @wheat = 0, @ore = 0)
  end

  def add(resource : Resource, amount : Int32 = 1) : Nil
    case resource
    when .wood?  then @wood += amount
    when .brick? then @brick += amount
    when .sheep? then @sheep += amount
    when .wheat? then @wheat += amount
    when .ore?   then @ore += amount
    else
      # desert is not a bankable resource
    end
  end

  def remove(resource : Resource, amount : Int32 = 1) : Nil
    raise "insufficient #{resource} in bank" unless count(resource) >= amount
    add(resource, -amount)
  end

  def count(resource : Resource) : Int32
    case resource
    when .wood?  then @wood
    when .brick? then @brick
    when .sheep? then @sheep
    when .wheat? then @wheat
    when .ore?   then @ore
    else
      0
    end
  end

  def total : Int32
    @wood + @brick + @sheep + @wheat + @ore
  end

  def empty? : Bool
    total.zero?
  end

  def each_nonzero(& : Resource, Int32 ->) : Nil
    yield Resource::Wood, @wood if @wood > 0
    yield Resource::Brick, @brick if @brick > 0
    yield Resource::Sheep, @sheep if @sheep > 0
    yield Resource::Wheat, @wheat if @wheat > 0
    yield Resource::Ore, @ore if @ore > 0
  end

  def to_json_payload
    {
      wood:  @wood,
      brick: @brick,
      sheep: @sheep,
      wheat: @wheat,
      ore:   @ore,
      total: total,
    }
  end
end

enum BuildingKind
  Settlement
  City
end

struct PlayerId
  getter value : String

  def initialize(@value : String); end

  def_equals_and_hash @value

  def to_s(io : IO) : Nil
    io << @value
  end
end
