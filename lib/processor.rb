
require 'set'

class Object
   # The hidden singleton lurks behind everyone
   def metaclass; class << self; self; end; end
   def meta_eval &blk; metaclass.instance_eval &blk; end

   # Adds methods to a metaclass
   def meta_def name, &blk
     meta_eval { define_method name, &blk }
   end

   # Defines an instance method within a class
   def class_def name, &blk
     class_eval { define_method name, &blk }
   end
 end
 
class GeneratorFactory
	def self.get_generator(array = nil, &block)
		if defined? Fiber
			return FiberWrapper.new(&block)
		else
			return GeneratorWrapper.new(&block)
		end
	end
end

# Ruby 1.9 only supports Fibers
class FiberWrapper
	def initialize(&block)
		@fiber = Fiber.new &block
	end
	
	def resume
		@fiber.resume
	end
	
	def yield(*data)
		Fiber.yield(data)
	end
	
end

# Ruby 1.8 only supports Generators
class GeneratorWrapper
	class StartSignal; end
	class EndSignal; end
	def initialize(&block)
		require 'generator'
		
		# We need to explicitly yield an value and ignore it.
		@first = true
		@generator = Generator.new {|g| g.yield(StartSignal); block.call; g.yield(EndSignal) }
	end
	
	def resume
		value = @generator.next
		
		# Skip the start signal
		value = @generator.next if value == StartSignal
		
		# The fiber has finished running, quit
		return if value == EndSignal
		
		# The fiber yielded a single value, return it
		return value[0] if value.length == 1
		
		# The fiber yielded multiple values, return them
		return value
	end
	
	def yield(*data)
		@generator.yield(data)
	end
end

$PROCESSOR_DEBUG = false
class Processor
	attr_accessor :source
	
	def initialize(args = {}, &block)
		@name = args[:name]
		@source = args[:source]
		@block = block
	end
	
	def next
		generator.resume
	end
	
	def |(other)
      other.source = self
      other
    end 
	
	def each
		while value = self.next
			yield(value)
		end
	end
	
	def name; @name || self.class.name; end
	def name=val; @name = val; end
	
	protected
	def yield(value)
		generator.yield(value)
	end
	
	private
	def generator
		@generator ||= GeneratorFactory.get_generator { process }
	end
	
	def process
		while value = source.next
			value = handle(value)
			self.yield(value) if value
		end
	end
	
	def handle(value)
		value = @block.call(value) if @block
		value
	end
end

class Source < Processor
	def initialize(*args, &block)
		@block = block
		@data = []
		@data = args.shift unless block_given?
		super(*args)
	end
	def process
		instance_eval &@block if @block
		@data.each {|e| self.yield(e)}
	end
end
class Filter < Processor
	def initialize(*args, &block)
		super(*args)
		@filter = block
	end
	def filter(obj)
		@filter.call(obj)
	end
	def handle(obj)
		return nil unless filter(obj)
		obj
	end
end

class HashProxy
	attr_reader :hash
	
	def initialize(hash = {})
		@hash = hash
		@rejected = false
	end
	
	def reject!
		@rejected = true
	end
	def rejected?; @rejected end
	
	def method_missing(m, *args)
		return @hash[m] if is_getter?(m, args)
		return @hash[m.to_s[0...-1].to_sym] = args[0] if is_setter?(m, args)
		super(m, args)
	end
	
	def self.create_strict_proxy_class(getters, setters, caller_name)
		proxy_class = Class.new(StrictHashProxy)
		proxy_class.class_eval { @setters = setters; @getters = getters; @caller = caller_name }
		return proxy_class
	end
	
	class StrictHashProxy < HashProxy
		def self.setters; @setters; end
		def self.getters; @getters; end
		def self.caller; @caller; end
		
		def method_missing(m, *args)
			if is_setter?(m, args) && !self.class.setters.include?(m.to_s[0...-1].to_sym)
				raise NoMethodError, "#{self.class.caller} can't write to '#{m.to_s[0...-1]}'. Perhaps you need to add it to the provides list."
			elsif is_getter?(m, args) && !self.class.getters.include?(m)
				raise NoMethodError, "#{self.class.caller} can't access '#{m.to_s}'. Please add it to your requires list."
			end
			super(m, *args)
		end
	end
	
	private
	def is_setter?(m, args)
		m.to_s[-1, 1] == "=" && args.length == 1
	end
	def is_getter?(m, args)
		@hash[m] && args.length == 0
	end
end


class HashProcessor < Processor
	def output(hash = {})
		obj = self.class.proxy_class.new hash
		
		yield(obj) if block_given?
		
		raise "#{name} forgot to provide value for '#{p}'" if p = self.class.provides.find {|p| obj.hash[p].nil?}
		@generator.yield(obj.hash) unless obj.rejected?
	end
	def process
		while hash = input
			raise "#{name} requires a value for '#{p}" if p = self.class.requires.find {|p| hash[p].nil?}
			output(hash) { |o| process_object(o) }
		end
	end 
	
	def self.strict?
		return @strict unless @strict.nil?
		return requires.length > 0 || provides.length > 0
	end
	def self.strict= val; @strict = val; end
	def self.requires(*params)
		@requires ||= Set.new
		@requires.merge(params)
	end
	def self.provides(*params)
		@provides ||= Set.new
		@provides.merge(params)
	end
	def self.proxy_class
		return @proxy_class if @proxy_class
		
		return @proxy_class = HashProxy unless strict?
		
		accessors = Set.new.merge(requires).merge(provides)
		@proxy_class = HashProxy.create_strict_proxy_class(accessors, provides, self.name)
	end
end