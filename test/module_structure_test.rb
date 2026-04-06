# frozen_string_literal: true

require "minitest/autorun"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rsv"

# ── 模块结构测试 ─────────────────────────────────────────────────────────────
# 覆盖: class-based module, definition/instance, 去重, 自动布线,
#       module_name override, local wire interconnect, direct connections

module ModuleStructureTestFixtures
  class Counter < RSV::ModuleDef
    def initialize(width: 8)
      super()

      clk = input("clk", bit)
      rst = input("rst", bit)
      count = output("count", uint(width))
      count_r = reg("count_r", uint(width), init: 0)

      count <= count_r

      with_clk_and_rst(clk, rst)
      always_ff do
        svif(1) do
          count_r <= count_r + 1
        end
      end
    end
  end

  class Top < RSV::ModuleDef
    def initialize
      super()

      clk = input("clk", bit)
      rst = input("rst", bit)
      count = output("count", uint(8))

      u_counter = Counter.new(inst_name: "u_counter", width: 8)
      u_counter.clk <= clk
      u_counter.rst <= rst
      count <= u_counter.count
    end
  end
end

class ModuleStructureTest < Minitest::Test
  def test_module_def_must_be_subclassed
    assert_raises(ArgumentError) do
      RSV::ModuleDef.new("Legacy") do
      end
    end
  end

  def test_to_sv_can_write_to_stdout_with_dash
    mod = ModuleStructureTestFixtures::Counter.new(width: 8)
    expected = <<~SV.chomp
      module Counter (
        input  logic       clk,
        input  logic       rst,
        output logic [7:0] count
      );

        logic [7:0] count_r;

        assign count = count_r;

        always_ff @(posedge clk or posedge rst) begin
          if (rst) begin
            count_r <= 8'h0;
          end else if (1) begin
            count_r <= count_r + 8'd1;
          end
        end

      endmodule
    SV

    stdout, = capture_io do
      assert_equal expected, mod.to_sv("-")
    end

    assert_equal "#{expected}\n", stdout
  end

  def test_submodule_class_instances_allow_late_port_connections
    top = ModuleStructureTestFixtures::Top.new
    expected = <<~SV.chomp
      module Top (
        input  logic       clk,
        input  logic       rst,
        output logic [7:0] count
      );

        Counter u_counter (
          .clk(clk),
          .rst(rst),
          .count(count)
        );

      endmodule
    SV

    refute_respond_to top, :instantiate
    refute_respond_to top, :assign_stmt
    refute_respond_to top, :logic
    assert_equal expected, top.to_sv
  end

  def test_build_can_override_module_name
    named_counter_class = Class.new(RSV::ModuleDef) do
      define_singleton_method(:name) { "NamedCounter" }

      define_method(:build) do |width: 8|
        self.module_name = "NamedCounterW#{width}"

        clk = input("clk", bit)
        rst = input("rst", bit)
        count = output("count", uint(width))
        count_r = reg("count_r", uint(width), init: 0)

        count <= count_r

        with_clk_and_rst(clk, rst)
        always_ff do
          svif(1) do
            count_r <= count_r + 1
          end
        end
      end
    end

    mod = named_counter_class.new(width: 16)

    assert_equal "NamedCounterW16", mod.module_name
    assert_match(/\Amodule NamedCounterW16 \(/, mod.to_sv)
  end

  def test_identical_variants_reuse_base_name_and_distinct_variants_get_suffix
    counter_class = Class.new(RSV::ModuleDef) do
      define_singleton_method(:name) { "VariantCounter" }

      define_method(:build) do |width: 8|
        clk = input("clk", bit)
        rst = input("rst", bit)
        count = output("count", uint(width))
        count_r = reg("count_r", uint(width), init: 0)

        count <= count_r

        with_clk_and_rst(clk, rst)
        always_ff do
          svif(1) do
            count_r <= count_r + 1
          end
        end
      end
    end

    counter_8_a = counter_class.new(width: 8)
    counter_8_b = counter_class.new(width: 8)
    counter_16 = counter_class.new(width: 16)

    assert_equal "VariantCounter", counter_8_a.module_name
    assert_equal "VariantCounter", counter_8_b.module_name
    assert_equal "VariantCounter_1", counter_16.module_name

    top_class = Class.new(RSV::ModuleDef) do
      define_singleton_method(:name) { "VariantTop" }

      define_method(:build) do
        clk = input("clk", bit)
        rst = input("rst", bit)
        count_a = output("count_a", uint(8))
        count_b = output("count_b", uint(8))
        count_c = output("count_c", uint(16))

        counter_a = counter_class.new(inst_name: "u_counter_a", width: 8)
        counter_b = counter_class.new(inst_name: "u_counter_b", width: 8)
        counter_c = counter_class.new(inst_name: "u_counter_c", width: 16)

        counter_a.clk <= clk
        counter_a.rst <= rst
        count_a <= counter_a.count

        counter_b.clk <= clk
        counter_b.rst <= rst
        count_b <= counter_b.count

        counter_c.clk <= clk
        counter_c.rst <= rst
        count_c <= counter_c.count
      end
    end

    top_sv = top_class.new.to_sv

    assert_includes top_sv, "VariantCounter u_counter_a ("
    assert_includes top_sv, "VariantCounter u_counter_b ("
    assert_includes top_sv, "VariantCounter_1 u_counter_c ("
  end

  def test_manual_definition_handle_reuses_template_without_rebuilding
    counter_class = Class.new(RSV::ModuleDef) do
      @build_count = 0

      class << self
        attr_reader :build_count

        def increment_build_count
          @build_count ||= 0
          @build_count += 1
        end
      end

      define_singleton_method(:name) { "ManualCounter" }

      define_method(:build) do |width: 8|
        self.class.increment_build_count

        clk = input("clk", bit)
        rst = input("rst", bit)
        count = output("count", uint(width))
        count_r = reg("count_r", uint(width), init: 0)

        count <= count_r

        with_clk_and_rst(clk, rst)
        always_ff do
          svif(1) do
            count_r <= count_r + 1
          end
        end
      end
    end

    counter_def = counter_class.definition(width: 8)

    top_class = Class.new(RSV::ModuleDef) do
      define_singleton_method(:name) { "ManualTop" }

      define_method(:build) do |counter_def:|
        clk = input("clk", bit)
        rst = input("rst", bit)
        count_a = output("count_a", uint(8))
        count_b = output("count_b", uint(8))

        counter_a = instance(counter_def, inst_name: "u_counter_a")
        counter_b = instance(counter_def, inst_name: "u_counter_b")

        counter_a.clk <= clk
        counter_a.rst <= rst
        count_a <= counter_a.count

        counter_b.clk <= clk
        counter_b.rst <= rst
        count_b <= counter_b.count
      end
    end

    top_sv = top_class.new(counter_def: counter_def).to_sv

    assert_equal 1, counter_class.build_count
    assert_equal "ManualCounter", counter_def.module_name
    assert_match(/\Amodule ManualCounter \(/, counter_def.to_sv)
    assert_equal 2, top_sv.scan("ManualCounter u_counter").length
  end

  def test_definition_can_wrap_a_prebuilt_module_template
    counter_class = Class.new(RSV::ModuleDef) do
      @build_count = 0

      class << self
        attr_reader :build_count

        def increment_build_count
          @build_count ||= 0
          @build_count += 1
        end
      end

      define_singleton_method(:name) { "WrappedCounter" }

      define_method(:build) do |width: 8|
        self.class.increment_build_count
        clk = input("clk", bit)
        rst = input("rst", bit)
        count = output("count", uint(width))
        count_r = reg("count_r", uint(width), init: 0)

        count <= count_r

        with_clk_and_rst(clk, rst)
        always_ff do
          svif(1) do
            count_r <= count_r + 1
          end
        end
      end
    end

    counter_template = counter_class.new(width: 16)

    top_class = Class.new(RSV::ModuleDef) do
      define_singleton_method(:name) { "WrappedTop" }

      define_method(:build) do |counter_template:|
        clk = input("clk", bit)
        rst = input("rst", bit)
        count = output("count", uint(16))
        counter_def = definition(counter_template)
        counter = instance(counter_def, inst_name: "u_counter")

        counter.clk <= clk
        counter.rst <= rst
        count <= counter.count
      end
    end

    top_sv = top_class.new(counter_template: counter_template).to_sv

    assert_equal 1, counter_class.build_count
    assert_includes top_sv, "WrappedCounter u_counter ("
  end

  def test_definition_reuses_the_same_handle_for_identical_templates
    counter_class = Class.new(RSV::ModuleDef) do
      define_singleton_method(:name) { "DuplicateCounter" }

      define_method(:build) do |width: 8|
        clk = input("clk", bit)
        rst = input("rst", bit)
        count = output("count", uint(width))
        count_r = reg("count_r", uint(width), init: 0)

        count <= count_r

        with_clk_and_rst(clk, rst)
        always_ff do
          svif(1) do
            count_r <= count_r + 1
          end
        end
      end
    end

    counter_8_def = counter_class.definition(width: 8)
    counter_16_def = counter_class.definition(width: 16)

    refute_equal counter_8_def.module_name, counter_16_def.module_name
  end

  def test_submodules_can_be_connected_through_parent_local_wire
    stage_class = Class.new(RSV::ModuleDef) do
      define_singleton_method(:name) { "PipelineStage" }

      define_method(:build) do
        din = input("din", uint(8))
        dout = output("dout", uint(8))

        dout <= din
      end
    end

    top_class = Class.new(RSV::ModuleDef) do
      define_singleton_method(:name) { "InterconnectTop" }

      define_method(:build) do
        din = input("din", uint(8))
        dout = output("dout", uint(8))
        stage_link = wire("stage_link", uint(8))

        stage_a = stage_class.new(inst_name: "u_stage_a")
        stage_b = stage_class.new(inst_name: "u_stage_b")

        stage_a.din <= din
        stage_link <= stage_a.dout
        stage_b.din <= stage_link
        dout <= stage_b.dout
      end
    end

    top_sv = top_class.new.to_sv

    assert_includes top_sv, "logic [7:0] stage_link;"
    assert_includes top_sv, ".dout(stage_link)"
    assert_includes top_sv, ".din(stage_link)"
  end

  def test_direct_submodule_connections_auto_generate_intermediate_wire
    stage_class = Class.new(RSV::ModuleDef) do
      define_singleton_method(:name) { "DirectStage" }

      define_method(:build) do
        din = input("din", uint(8))
        dout = output("dout", uint(8))

        dout <= din
      end
    end

    top_class = Class.new(RSV::ModuleDef) do
      define_singleton_method(:name) { "DirectInterconnectTop" }

      define_method(:build) do
        din = input("din", uint(8))
        dout = output("dout", uint(8))

        stage_a = stage_class.new(inst_name: "u_stage_a")
        stage_b = stage_class.new(inst_name: "u_stage_b")

        stage_a.din <= din
        stage_a.dout <= stage_b.din
        dout <= stage_b.dout
      end
    end

    top_sv = top_class.new.to_sv

    assert_includes top_sv, "logic [7:0] u_stage_a_dout;"
    assert_includes top_sv, ".dout(u_stage_a_dout)"
    assert_includes top_sv, ".din(u_stage_a_dout)"
  end

  def test_indexed_instance_port_connections_auto_generate_named_wires_for_multidim_arrays
    producer_class = Class.new(RSV::ModuleDef) do
      define_singleton_method(:name) { "ArrayProducer" }

      define_method(:build) do
        output("tx_mem", mem([2, 3], uint(8)))
      end
    end

    consumer_class = Class.new(RSV::ModuleDef) do
      define_singleton_method(:name) { "ArrayConsumer" }

      define_method(:build) do
        input("rx_mem", mem([2, 3], uint(8)))
      end
    end

    top_class = Class.new(RSV::ModuleDef) do
      define_singleton_method(:name) { "ArrayInterconnectTop" }

      define_method(:build) do
        producer = producer_class.new(inst_name: "u_producer")
        consumer = consumer_class.new(inst_name: "u_consumer")

        producer.tx_mem[0][1] <= consumer.rx_mem[1][2]
      end
    end

    top_sv = top_class.new.to_sv

    assert_includes top_sv, "logic [7:0] u_producer_tx_mem[1:0][2:0];"
    assert_includes top_sv, "logic [7:0] u_consumer_rx_mem[1:0][2:0];"
    assert_includes top_sv, "logic [7:0] u_producer_tx_mem_0_1;"
    assert_includes top_sv, "assign u_producer_tx_mem_0_1   = u_producer_tx_mem[0][1];"
    assert_includes top_sv, "assign u_consumer_rx_mem[1][2] = u_producer_tx_mem_0_1;"
    assert_includes top_sv, ".tx_mem(u_producer_tx_mem)"
    assert_includes top_sv, ".rx_mem(u_consumer_rx_mem)"
  end

  # ── handlers_can_be_used_in_instance_connections (from handler_dsl) ────

  def test_handlers_can_be_used_in_instance_connections
    counter_class = Class.new(RSV::ModuleDef) do
      define_singleton_method(:name) { "Counter" }

      define_method(:build) do
        clk = input("clk", bit)
        count = output("count", uint(16))
      end
    end

    mod = Class.new(RSV::ModuleDef) do
      define_singleton_method(:name) { "Top" }

      define_method(:build) do
        clk = input("clk", bit)
        count = wire("count", uint(16))

        counter = counter_class.new(inst_name: "u_counter")
        counter.clk <= clk
        count <= counter.count
      end
    end.new

    sv = mod.to_sv

    assert_includes sv, "Counter u_counter ("
    assert_includes sv, ".clk(clk)"
    assert_includes sv, ".count(count)"
  end
end
