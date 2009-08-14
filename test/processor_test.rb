require 'test/unit'
require 'Processor'

class TC_Generator < Test::Unit::TestCase
	def test_resume_should_call_block
		works = false
		@generator = GeneratorFactory.get_generator { works = true }
		@generator.resume
		assert works
	end
	
	def test_yield_should_deliver_data
		@generator = GeneratorFactory.get_generator { @generator.yield "Test" }
		result = @generator.resume
		assert_equal "Test", result
	end
	
	def test_yield_should_deliver_multiple_data
		@generator = GeneratorFactory.get_generator { @generator.yield 1, 2 }
		result = @generator.resume
		assert_equal [1, 2], result
	end
	
	def test_resume_should_work_multiple_times
		generator = GeneratorFactory.get_generator { generator.yield 1; generator.yield 2; }
		assert_equal 1, generator.resume
		assert_equal 2, generator.resume
	end
	
	def test_resume_should_return_nil_if_not_yielded
		generator = GeneratorFactory.get_generator { }
		assert_equal nil, generator.resume
	end
	
	def test_resume_should_work_after_last_yield
		generator = GeneratorFactory.get_generator { generator.yield 1 }
		assert_equal 1, generator.resume
		assert_equal nil, generator.resume
	end
	
	def test_resume_should_cast_exception_after_processing
		generator = GeneratorFactory.get_generator { }
		assert_equal nil, generator.resume
		
		allowed_errors = [EOFError]
		allowed_errors.push FiberError if defined? FiberError
		
		assert_raise *allowed_errors do
			generator.resume
		end
	end
end

class TC_Source < Test::Unit::TestCase
	def test_empty_source
		s = Source.new []
		assert_nil s.next
	end
	def test_array_with_data
		s = Source.new [42, "asdf"]
		assert_equal 42, s.next
		assert_equal "asdf", s.next
	end
	def test_array_ends_with_nil
		s = Source.new [42]
		assert_equal 42, s.next
		assert_nil s.next
	end
	def test_empty_block
		s = Source.new { }
		assert_nil s.next
	end
	def test_each
		s = Source.new [42]
		s.each {|v| assert_equal 42, v}
	end
	def test_block
		s = Source.new { self.yield(42) }
		assert_equal 42, s.next
		assert_nil s.next
	end
	def test_inheriting
		s = Class.new(Source).new
		s.meta_def(:process){ self.yield(42) }
		assert_equal 42, s.next
		assert_nil s.next
	end
end
class TC_Filter < Test::Unit::TestCase
	def setup
		@source = Source.new [1,2,3]
	end
	def test_filter
		f = @source | Filter.new {|v| v > 2}
		assert_equal 3, f.next
		assert_nil f.next
	end
	def test_inheriting
		f = @source | Class.new(Filter).new
		f.meta_def(:filter) {|v| v % 2 == 0}
		assert_equal 2, f.next
		assert_nil f.next
	end
	
end
class TC_Processor < Test::Unit::TestCase
	def setup
		@source = Source.new [1, 2]
	end
	
	def test_generic_processor
		p = @source | Processor.new {|v| v+2}
		assert_equal 3, p.next
		assert_equal 4, p.next
		assert_nil p.next
	end
	def test_inherited_handler
		p = @source | Class.new(Processor).new
		p.meta_def(:handle) {|v| v+40}
		assert_equal 41, p.next
		assert_equal 42, p.next
		assert_nil p.next
	end
	def test_inherited_processor
		p = @source | Class.new(Processor).new
		p.meta_def(:process) do
			source.next
			self.yield(40+source.next)
		end
		assert_equal 42, p.next
		assert_nil p.next
	end
end

class TC_ProxyObject < Test::Unit::TestCase
	class TestHashProcessor < HashProcessor
		requires :url
		provides :rss
	end
	def test_reject_should_be_rejected
		obj = HashProxy.new
		assert !obj.rejected?
		obj.reject!
		assert obj.rejected?
	end
	def test_base_provides_should_be_empty
		assert 0, HashProcessor.provides.length
	end
	def test_base_requires_should_be_empty
		assert 0, HashProcessor.requires.length
	end
	def test_requires_should_create_accessor
		obj = TestHashProcessor.proxy_class.new({:url => "Url"})
		assert "Url", obj.url
	end
	def test_provides_should_create_setter_and_getter
		obj = TestHashProcessor.proxy_class.new({:url => "Url"})
		obj.rss = "Test"
		assert "Test", obj.rss
	end
	
	def test_should_return_hash
		obj = TestHashProcessor.proxy_class.new({:url => "Url"})
		obj.rss = "Test"
		assert "Test", obj.hash[:rss]
		assert "Url", obj.hash[:url]
	end
	def test_should_keep_existing_properties
		obj = TestHashProcessor.proxy_class.new({:other => 5})
		obj.rss = "Test"
		assert 2, obj.hash[:other]
	end
	def test_if_not_available_get_error_in_debug
		obj = TestHashProcessor.proxy_class.new({:other => 5})
		assert_raise(NoMethodError) { obj.other }
		assert_raise(NoMethodError) { obj.other = "Test" }
	end
end

class TC_HashProcessor < Test::Unit::TestCase
	class Adder < HashProcessor
		requires :numberA
		provides :result
		def process_object(obj)
			obj.result = obj.numberA + 10
		end
	end
	
	def test_adder
		source = Source.new [{:numberA => 2}]
		adder = source | Adder.new
		hash = adder.resume
		assert_equal 12, hash[:result]
	end
	
	def test_generic_processor
		source = Source.new [{:numberA => 10}]
		chain = source | HashProcessor.new {|obj| obj.result = obj.numberA + 5 }
		hash = chain.resume
		assert_equal 15, hash[:result]
	end
end


=begin
Source.new []
Source.new do; self.yield(val); end
class MySource < Source
	def process; self.yield(val); end
end

Filter.new {|v| v > 3}
class MyFilter < Filter
	def filter(val); return val > 3; end
end

Processor.new {|i| i + 3}
class MyProcessor < Processor
	def handle(val); val+2; end
end

class MyFooProcessor < Processor
	def process; while v = input; self.yield(v + 2); end; end
end

ObjectSource.new [{:dude=>5},{:dude=>2}]
ObjectSource.new do
	self.yield do |o|
		o.dude = 3
	end
end
ObjectSource.new do
	self.yield {:test => 3, :lol => 2}
end

ObjectFilter.new {|o| o.test < 3}
class MyFilter < ObjectFilter
	def filter(obj); obj.test < 5; end
end

ObjectProcessor.new {|obj| obj.foo = obj.dope + 2; obj.reject!}
class MyProcessor < ObjectProcessor
	def handle(obj)
		obj.foo = obj.bar + 5
		obj.reject!
	end
end
class MyProcessor < ObjectProcessor
	def process
		each_input do |obj|
			obj.dude = obj.rss
		end
	end
end


Source.new [5,3,2]
Source.new { self.yield(5); self.yield(3); self.yield(2) }

class RssSource < Source
	def process
		self.yield(5)
		self.yield(3)
		self.yield(2)
	end
end
Filter.new {|o| o < 3}

Mapper.new :rss => :title, :pop => :dude

HashProcessor


source = RssSource.new "http://visir.is/rss"




=end
