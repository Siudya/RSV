# frozen_string_literal: true

module RSV
  module ExprOps
    def +(other)
      BinaryExpr.new(self, :+, RSV.normalize_expr(other))
    end

    def -(other)
      BinaryExpr.new(self, :-, RSV.normalize_expr(other))
    end

    def *(other)
      BinaryExpr.new(self, :*, RSV.normalize_expr(other))
    end

    def /(other)
      BinaryExpr.new(self, :/, RSV.normalize_expr(other))
    end

    def %(other)
      BinaryExpr.new(self, :%, RSV.normalize_expr(other))
    end

    def <<(other)
      BinaryExpr.new(self, :<<, RSV.normalize_expr(other))
    end

    def >>(other)
      BinaryExpr.new(self, :>>, RSV.normalize_expr(other))
    end

    def &(other)
      BinaryExpr.new(self, :&, RSV.normalize_expr(other))
    end

    def |(other)
      BinaryExpr.new(self, :|, RSV.normalize_expr(other))
    end

    def ^(other)
      BinaryExpr.new(self, :^, RSV.normalize_expr(other))
    end

    def lt(other)
      BinaryExpr.new(self, :<, RSV.normalize_expr(other))
    end

    def le(other)
      BinaryExpr.new(self, :<=, RSV.normalize_expr(other))
    end

    def gt(other)
      BinaryExpr.new(self, :>, RSV.normalize_expr(other))
    end

    def ge(other)
      BinaryExpr.new(self, :>=, RSV.normalize_expr(other))
    end

    def eq(other)
      BinaryExpr.new(self, :==, RSV.normalize_expr(other))
    end

    def ne(other)
      BinaryExpr.new(self, :!=, RSV.normalize_expr(other))
    end

    define_method(:and) do |other|
      BinaryExpr.new(self, :logic_and, RSV.normalize_expr(other))
    end

    define_method(:or) do |other|
      BinaryExpr.new(self, :logic_or, RSV.normalize_expr(other))
    end

    def !@
      UnaryExpr.new(:!, self)
    end

    def ~
      UnaryExpr.new(:~, self)
    end

    def or_r
      UnaryExpr.new(:reduce_or, self)
    end

    def and_r
      UnaryExpr.new(:reduce_and, self)
    end

    def sv_stream
      SvStream.from(self)
    end

    def sv_take(count)
      sv_stream.sv_take(count)
    end

    def sv_select(&block)
      sv_stream.sv_select(&block)
    end

    def sv_foreach(&block)
      sv_stream.sv_foreach(&block)
    end

    def sv_reduce(&block)
      sv_stream.sv_reduce(&block)
    end

    def sv_map(&block)
      sv_stream.sv_map(&block)
    end

    def [](*args)
      if RSV.index_only_expr?(self)
        unless args.length == 1 && !args[0].is_a?(Range)
          raise ArgumentError, "array and memory selections only support a single index while dimensions remain"
        end

        idx = args[0]
        RSV.validate_index(idx)
        return IndexExpr.new(self, RSV.normalize_expr(idx))
      end

      case args.length
      when 1
        index_or_range = args[0]
        if index_or_range.is_a?(Range)
          raise ArgumentError, "exclusive ranges are not supported in RSV bit selects" if index_or_range.exclude_end?

          return range_select(index_or_range.begin, index_or_range.end)
        end

        IndexExpr.new(self, RSV.normalize_expr(index_or_range))
      when 2
        range_select(args[0], args[1])
      when 3
        indexed_select(args[0], args[1], args[2])
      else
        raise ArgumentError, "[] expects index, range, msb/lsb, or base/direction/width"
      end
    end

    private

    def range_select(msb, lsb)
      RangeSelectExpr.new(self, msb, lsb)
    end

    def indexed_select(base, direction, width)
      unless [:+, :-].include?(direction)
        raise ArgumentError, "indexed part select expects :+ or :- direction"
      end

      IndexedPartSelectExpr.new(self, base, direction, width)
    end
  end

  module AssignableExpr
    def <=(rhs)
      builder = RSV.current_procedural_builder
      return builder.send(:append_assignment, self, rhs) if builder

      mod = RSV.current_module_def
      raise "assignment is only valid inside module definitions" unless mod

      mod.send(:append_assignment, self, rhs)
    end

    def >=(lhs)
      builder = RSV.current_procedural_builder
      return builder.send(:append_assignment, lhs, self) if builder

      mod = RSV.current_module_def
      raise "assignment is only valid inside module definitions" unless mod

      mod.send(:append_assignment, lhs, self)
    end
  end

  class DataTypeFactory
    def initialize(module_def, storage)
      @module_def = module_def
      @storage = storage
    end

    def fill(*dims_and_type)
      @module_def.send(:compose_data_type, *dims_and_type, storage: @storage)
    end
  end

  # Anonymous RSV data type used to define named hardware objects.
  # Non-hardware DataType instances with init values support Ruby-time arithmetic.
  class DataType
    attr_reader :width, :signed, :init, :packed_dims, :unpacked_dims

    def initialize(width:, signed: false, init: nil, packed_dims: [], unpacked_dims: [])
      @width = width
      @signed = signed
      @init = init
      @packed_dims = packed_dims.dup
      @unpacked_dims = unpacked_dims.dup
    end

    def append_dimensions(packed: [], unpacked: [])
      DataType.new(
        width: @width,
        signed: @signed,
        init: @init,
        packed_dims: @packed_dims + packed,
        unpacked_dims: @unpacked_dims + unpacked
      )
    end

    def as_sint
      AsSintExpr.new(self)
    end

    def scalar?
      @packed_dims.empty? && @unpacked_dims.empty? && @width.is_a?(Integer) && !@init.nil? && @init.is_a?(Integer)
    end

    def +(other)
      other = coerce_data_type(other)
      raise ArgumentError, "runtime arithmetic requires scalar types with init" unless scalar? && other.scalar?

      val = @init + other.init
      w = [@width, other.width].max + 1
      DataType.new(width: w, signed: @signed || other.signed, init: val & ((1 << w) - 1))
    end

    def -(other)
      other = coerce_data_type(other)
      raise ArgumentError, "runtime arithmetic requires scalar types with init" unless scalar? && other.scalar?

      val = @init - other.init
      w = [@width, other.width].max + 1
      val = val & ((1 << w) - 1)
      DataType.new(width: w, signed: @signed || other.signed, init: val)
    end

    def *(other)
      other = coerce_data_type(other)
      raise ArgumentError, "runtime arithmetic requires scalar types with init" unless scalar? && other.scalar?

      val = @init * other.init
      w = @width + other.width
      DataType.new(width: w, signed: @signed || other.signed, init: val & ((1 << w) - 1))
    end

    def /(other)
      other = coerce_data_type(other)
      raise ArgumentError, "runtime arithmetic requires scalar types with init" unless scalar? && other.scalar?
      raise ZeroDivisionError, "division by zero" if other.init == 0

      val = @init / other.init
      DataType.new(width: @width, signed: @signed || other.signed, init: val & ((1 << @width) - 1))
    end

    def %(other)
      other = coerce_data_type(other)
      raise ArgumentError, "runtime arithmetic requires scalar types with init" unless scalar? && other.scalar?

      val = @init % other.init
      DataType.new(width: other.width, signed: @signed || other.signed, init: val & ((1 << other.width) - 1))
    end

    def &(other)
      other = coerce_data_type(other)
      raise ArgumentError, "runtime arithmetic requires scalar types with init" unless scalar? && other.scalar?

      w = [@width, other.width].max
      DataType.new(width: w, signed: false, init: (@init & other.init) & ((1 << w) - 1))
    end

    def |(other)
      other = coerce_data_type(other)
      raise ArgumentError, "runtime arithmetic requires scalar types with init" unless scalar? && other.scalar?

      w = [@width, other.width].max
      DataType.new(width: w, signed: false, init: (@init | other.init) & ((1 << w) - 1))
    end

    def ^(other)
      other = coerce_data_type(other)
      raise ArgumentError, "runtime arithmetic requires scalar types with init" unless scalar? && other.scalar?

      w = [@width, other.width].max
      DataType.new(width: w, signed: false, init: (@init ^ other.init) & ((1 << w) - 1))
    end

    def <<(n)
      raise ArgumentError, "runtime shift requires scalar type with init" unless scalar?
      n = n.is_a?(DataType) ? n.init : n

      DataType.new(width: @width, signed: @signed, init: (@init << n) & ((1 << @width) - 1))
    end

    def >>(n)
      raise ArgumentError, "runtime shift requires scalar type with init" unless scalar?
      n = n.is_a?(DataType) ? n.init : n

      DataType.new(width: @width, signed: @signed, init: @init >> n)
    end

    def ~
      raise ArgumentError, "runtime bitwise not requires scalar type with init" unless scalar?

      DataType.new(width: @width, signed: @signed, init: (~@init) & ((1 << @width) - 1))
    end

    def or_r
      raise ArgumentError, "runtime reduce requires scalar type with init" unless scalar?

      DataType.new(width: 1, signed: false, init: @init != 0 ? 1 : 0)
    end

    def and_r
      raise ArgumentError, "runtime reduce requires scalar type with init" unless scalar?

      mask = (1 << @width) - 1
      DataType.new(width: 1, signed: false, init: (@init & mask) == mask ? 1 : 0)
    end

    def eq(other)
      other = coerce_data_type(other)
      raise ArgumentError, "runtime compare requires scalar types with init" unless scalar? && other.scalar?

      DataType.new(width: 1, signed: false, init: @init == other.init ? 1 : 0)
    end

    def ne(other)
      other = coerce_data_type(other)
      raise ArgumentError, "runtime compare requires scalar types with init" unless scalar? && other.scalar?

      DataType.new(width: 1, signed: false, init: @init != other.init ? 1 : 0)
    end

    private

    def coerce_data_type(other)
      return other if other.is_a?(DataType)
      return DataType.new(width: bit_length(other), signed: other < 0, init: other) if other.is_a?(Integer)

      raise ArgumentError, "cannot coerce #{other.class} for DataType arithmetic"
    end

    def bit_length(val)
      return 1 if val == 0

      val.abs.bit_length + (val < 0 ? 1 : 0)
    end
  end

  # Wrapper that emits `$signed(xxx)` for unsigned-to-signed cast.
  class AsSintExpr
    include ExprOps

    attr_reader :operand

    def initialize(operand)
      @operand = RSV.normalize_expr(operand)
    end

    def width
      RSV.infer_expr_width(@operand)
    end
  end

  # Clock type marker for negedge support.
  class ClockSignal
    include ExprOps
    include AssignableExpr

    attr_reader :handler, :negated

    def initialize(handler, negated: false)
      @handler = handler
      @negated = negated
    end

    def neg
      ClockSignal.new(@handler, negated: true)
    end

    def name;         @handler.name end
    def width;        @handler.width end
    def signed;       @handler.signed end
    def kind;         @handler.kind end
    def init;         @handler.init end
    def packed_dims;   @handler.packed_dims end
    def unpacked_dims; @handler.unpacked_dims end
    def base_name;     @handler.base_name end
    def to_s;         @handler.to_s end
    def element_width;  @handler.element_width end
  end

  # Reset type marker for negedge / active-low support.
  class ResetSignal
    include ExprOps
    include AssignableExpr

    attr_reader :handler, :negated

    def initialize(handler, negated: false)
      @handler = handler
      @negated = negated
    end

    def neg
      ResetSignal.new(@handler, negated: true)
    end

    def name;         @handler.name end
    def width;        @handler.width end
    def signed;       @handler.signed end
    def kind;         @handler.kind end
    def init;         @handler.init end
    def packed_dims;   @handler.packed_dims end
    def unpacked_dims; @handler.unpacked_dims end
    def base_name;     @handler.base_name end
    def to_s;         @handler.to_s end
    def element_width;  @handler.element_width end
  end

  # Bit concatenation: {a, b, c}
  class CatExpr
    include ExprOps

    attr_reader :parts

    def initialize(parts)
      @parts = parts.map { |p| RSV.normalize_expr(p) }
    end

    def width
      widths = @parts.map { |p| RSV.infer_expr_width(p) }
      return nil if widths.any?(&:nil?)

      widths.sum
    end
  end

  # Bit replication: {n{a}}
  class FillExpr
    include ExprOps

    attr_reader :count, :part

    def initialize(count, part)
      @count = RSV.normalize_expr(count)
      @part  = RSV.normalize_expr(part)
    end

    def width
      count_val = @count.is_a?(LiteralExpr) ? @count.value : nil
      part_width = RSV.infer_expr_width(@part)
      return nil unless count_val.is_a?(Integer) && part_width

      count_val * part_width
    end
  end

  # Ternary mux expression: s ? a : b
  class MuxExpr
    include ExprOps

    attr_reader :sel, :a, :b

    def initialize(sel, a, b)
      @sel = RSV.normalize_expr(sel)
      @a   = RSV.normalize_expr(a)
      @b   = RSV.normalize_expr(b)
    end

    def width
      [RSV.infer_expr_width(@a), RSV.infer_expr_width(@b)].compact.max
    end
  end

  # Mux1h / MuxP statement (emits casez block)
  class MuxCaseStmt
    attr_reader :lhs, :sel, :dats, :case_type, :lsb_first

    def initialize(lhs, sel, dats, case_type:, lsb_first: true)
      @lhs      = lhs
      @sel      = sel
      @dats     = dats
      @case_type = case_type # :unique or :priority
      @lsb_first = lsb_first
    end
  end

  # Internal named signal declaration spec used by ports/locals.
  class SignalSpec
    attr_reader :name, :width, :signed, :init, :packed_dims, :unpacked_dims

    def initialize(name, width:, signed: false, init: nil, packed_dims: [], unpacked_dims: [])
      @name         = name
      @width        = width
      @signed       = signed
      @init         = init
      @packed_dims   = packed_dims.dup
      @unpacked_dims = unpacked_dims.dup
    end

    def append_dimensions!(packed: [], unpacked: [])
      @packed_dims.concat(packed)
      @unpacked_dims.concat(unpacked)
      self
    end

    def element_width
      @width
    end
  end

  class RawExpr
    include ExprOps

    attr_reader :source

    def initialize(source)
      @source = source
    end

    def to_s
      @source
    end
  end

  class LiteralExpr
    include ExprOps

    attr_reader :value, :width, :format

    def initialize(value, width: nil, format: :decimal)
      @value  = value
      @width  = width
      @format = format
    end

    def with_width(width)
      LiteralExpr.new(@value, width: width, format: @format)
    end

    def to_s
      @value.to_s
    end
  end

  class BinaryExpr
    include ExprOps

    attr_reader :lhs, :op, :rhs

    def initialize(lhs, op, rhs)
      @lhs = RSV.normalize_expr(lhs)
      @op  = op
      @rhs = RSV.normalize_expr(rhs)
    end
  end

  class UnaryExpr
    include ExprOps

    attr_reader :op, :operand

    def initialize(op, operand)
      @op = op
      @operand = RSV.normalize_expr(operand)
    end
  end

  class ParenExpr
    include ExprOps

    attr_reader :inner

    def initialize(inner)
      @inner = RSV.normalize_expr(inner)
    end

    def width
      RSV.infer_expr_width(@inner)
    end
  end

  class IndexExpr
    include ExprOps
    include AssignableExpr

    attr_reader :base, :index, :packed_dims, :unpacked_dims

    def initialize(base, index)
      @base = RSV.normalize_expr(base)
      @index = RSV.normalize_expr(index)
      @packed_dims = RSV.expr_packed_dims(@base).dup
      @unpacked_dims = RSV.expr_unpacked_dims(@base).dup
      @element_width = RSV.element_width(@base)

      if !@unpacked_dims.empty?
        @unpacked_dims = @unpacked_dims.drop(1)
      elsif !@packed_dims.empty?
        @packed_dims = @packed_dims.drop(1)
      else
        @element_width = 1
      end
    end

    def width
      RSV.flatten_packed_width(@element_width, @packed_dims) || (@packed_dims.empty? ? @element_width : nil)
    end

    def element_width
      @element_width
    end

    def base_name
      @base.base_name if @base.respond_to?(:base_name)
    end
  end

  class RangeSelectExpr
    include ExprOps
    include AssignableExpr

    attr_reader :base, :msb, :lsb

    def initialize(base, msb, lsb)
      @base = RSV.normalize_expr(base)
      @msb = RSV.normalize_expr(msb)
      @lsb = RSV.normalize_expr(lsb)
    end

    def width
      return nil unless @msb.is_a?(LiteralExpr) && @lsb.is_a?(LiteralExpr)

      (@msb.value - @lsb.value).abs + 1
    end

    def base_name
      @base.base_name if @base.respond_to?(:base_name)
    end
  end

  class IndexedPartSelectExpr
    include ExprOps
    include AssignableExpr

    attr_reader :base, :start, :direction, :part_width

    def initialize(base, start, direction, part_width)
      @base = RSV.normalize_expr(base)
      @start = RSV.normalize_expr(start)
      @direction = direction
      @part_width = RSV.normalize_expr(part_width)
    end

    def width
      case @part_width
      when LiteralExpr
        @part_width.value
      when RawExpr
        @part_width.source
      when SignalHandler
        @part_width.width
      else
        nil
      end
    end

    def base_name
      @base.base_name if @base.respond_to?(:base_name)
    end
  end

  StreamEntry = Struct.new(:expr, :index)

  class PackedCollectionExpr
    include ExprOps

    attr_reader :parts_low_to_high, :width, :signed, :packed_dims, :unpacked_dims

    def initialize(parts_low_to_high, width:, signed: false, packed_dims: [], unpacked_dims: [])
      @parts_low_to_high = parts_low_to_high.map { |part| RSV.normalize_expr(part) }
      @width = width
      @signed = signed
      @packed_dims = packed_dims.dup
      @unpacked_dims = unpacked_dims.dup
    end

    def element_width
      @width
    end
  end

  class SvStream
    def self.from(expr)
      expr = RSV.normalize_expr(expr)
      unpacked_dims = RSV.expr_unpacked_dims(expr)
      packed_dims = RSV.expr_packed_dims(expr)

      entries = if unpacked_dims.empty? && packed_dims.empty?
        build_scalar_entries(expr)
      elsif unpacked_dims.empty?
        build_packed_entries(expr, packed_dims.first)
      elsif packed_dims.empty? && unpacked_dims.length == 1
        build_unpacked_entries(expr, unpacked_dims.first)
      else
        raise ArgumentError, "sv_stream phase 2 only supports uint, packed arr, and single-dimension mem sources"
      end

      new(entries)
    end

    def self.build_scalar_entries(expr)
      width = RSV.infer_expr_width(expr)
      raise ArgumentError, "sv_stream requires a statically known width" unless width.is_a?(Integer) && width.positive?

      if expr.respond_to?(:signed) && expr.signed
        raise ArgumentError, "sv_stream phase 1 only supports unsigned scalar sources"
      end

      return [StreamEntry.new(expr, 0)] if width == 1

      (0...width).map { |i| StreamEntry.new(IndexExpr.new(expr, LiteralExpr.new(i)), i) }
    end

    def self.build_packed_entries(expr, dim)
      length = RSV.dimension_value(dim)
      raise ArgumentError, "sv_stream requires statically known packed dimensions" unless length.is_a?(Integer) && length.positive?

      (0...length).map { |i| StreamEntry.new(IndexExpr.new(expr, LiteralExpr.new(i)), i) }
    end

    def self.build_unpacked_entries(expr, dim)
      length = RSV.dimension_value(dim)
      raise ArgumentError, "sv_stream requires statically known unpacked dimensions" unless length.is_a?(Integer) && length.positive?

      (0...length).map { |i| StreamEntry.new(IndexExpr.new(expr, LiteralExpr.new(i)), i) }
    end

    attr_reader :entries

    def initialize(entries)
      @entries = entries.dup
    end

    def sv_take(count)
      raise ArgumentError, "sv_take expects a positive Integer" unless count.is_a?(Integer) && count.positive?
      raise ArgumentError, "sv_take count #{count} exceeds stream length #{@entries.length}" if count > @entries.length

      SvStream.new(@entries.first(count))
    end

    def sv_select
      raise ArgumentError, "sv_select requires a block" unless block_given?

      filtered = @entries.select do |entry|
        keep = yield(entry.expr, entry.index)
        unless keep == true || keep == false
          raise ArgumentError, "sv_select block must return true or false"
        end

        keep
      end
      SvStream.new(filtered)
    end

    def sv_foreach
      raise ArgumentError, "sv_foreach requires a block" unless block_given?

      @entries.each { |entry| yield(entry.expr, entry.index) }
      self
    end

    def sv_reduce
      raise ArgumentError, "sv_reduce requires a block" unless block_given?
      raise ArgumentError, "sv_reduce cannot operate on an empty stream" if @entries.empty?

      acc = @entries.first.expr
      @entries.drop(1).each_with_index do |entry, idx|
        lhs = idx.zero? ? acc : ParenExpr.new(acc)
        acc = RSV.normalize_expr(yield(lhs, entry.expr))
      end
      acc
    end

    def sv_map
      raise ArgumentError, "sv_map requires a block" unless block_given?
      raise ArgumentError, "sv_map cannot materialize an empty stream" if @entries.empty?

      mapped = @entries.map { |entry| RSV.normalize_expr(yield(entry.expr, entry.index)) }
      first = mapped.first
      expected_shape = RSV.expr_shape_signature(first)
      unless mapped.all? { |expr| RSV.expr_shape_signature(expr) == expected_shape }
        raise ArgumentError, "sv_map results must all have the same packed shape"
      end

      unpacked_dims = RSV.expr_unpacked_dims(first)
      unless unpacked_dims.empty?
        raise ArgumentError, "sv_map phase 1 only supports packed result shapes"
      end

      PackedCollectionExpr.new(
        mapped,
        width: RSV.element_width(first),
        signed: RSV.expr_signed(first),
        packed_dims: [mapped.length] + RSV.expr_packed_dims(first)
      )
    end
  end

  # Opaque handle returned from declarations and used to reference a signal.
  class SignalHandler
    include ExprOps
    include AssignableExpr

    attr_reader :name, :width, :signed, :kind, :init, :packed_dims, :unpacked_dims

    def initialize(name, width: 1, signed: false, kind: nil, init: nil, packed_dims: [], unpacked_dims: [])
      @name         = name
      @width        = width
      @signed       = signed
      @kind         = kind
      @init         = init
      @packed_dims   = packed_dims.dup
      @unpacked_dims = unpacked_dims.dup
    end

    def with_width(width)
      SignalHandler.new(
        @name,
        width: width,
        signed: @signed,
        kind: @kind,
        init: @init,
        packed_dims: @packed_dims,
        unpacked_dims: @unpacked_dims
      )
    end

    def append_dimensions!(packed: [], unpacked: [])
      @packed_dims.concat(packed)
      @unpacked_dims.concat(unpacked)
      self
    end

    def element_width
      @width
    end

    def to_s
      @name
    end

    def base_name
      @name
    end

    def as_sint
      AsSintExpr.new(self)
    end
  end

  class InstancePortHandler
    include AssignableExpr

    attr_reader :instance_handle, :port

    def initialize(instance_handle, port)
      @instance_handle = instance_handle
      @port = port
    end

    def name
      @port.name
    end

    def dir
      @port.dir
    end
  end

  class ModuleInstanceHandle
    attr_reader :definition, :inst_name, :params, :connections

    def initialize(definition, inst_name:)
      @definition = definition
      @inst_name = inst_name
      @params = definition.params.each_with_object({}) do |param, memo|
        memo[param.name] = param.value
      end
      @connections = {}
      @ports = definition.ports.each_with_object({}) do |port, memo|
        memo[port.name] = InstancePortHandler.new(self, port)
      end
    end

    def module_name
      @definition.name
    end

    def connect(port_name, signal)
      port_name = port_name.to_s
      raise ArgumentError, "unknown port #{port_name} on instance #{@inst_name}" unless @ports.key?(port_name)
      raise ArgumentError, "port #{port_name} on instance #{@inst_name} is already connected" if @connections.key?(port_name)

      @connections[port_name] = RSV.normalize_expr(signal)
    end

    def [](port_name)
      port_name = port_name.to_s
      @ports.fetch(port_name) do
        raise ArgumentError, "unknown port #{port_name} on instance #{@inst_name}"
      end
    end

    def method_missing(name, *args)
      return super unless args.empty? && @ports.key?(name.to_s)

      @ports[name.to_s]
    end

    def respond_to_missing?(name, include_private = false)
      @ports.key?(name.to_s) || super
    end
  end

  # Represents an input / output / inout port declaration.
  class PortDecl
    attr_reader :dir, :name, :width, :signed, :packed_dims, :unpacked_dims, :raw_type

    def initialize(dir, signal, raw_type: nil)
      @dir          = dir    # :input | :output | :inout
      @name         = signal.name
      @width        = signal.width  # Integer or String (e.g. "WIDTH")
      @signed       = signal.signed
      @packed_dims   = signal.packed_dims.dup
      @unpacked_dims = signal.unpacked_dims.dup
      @raw_type      = raw_type
    end

    def append_dimensions!(packed: [], unpacked: [])
      @packed_dims.concat(packed)
      @unpacked_dims.concat(unpacked)
      self
    end
  end

  # Represents a parameter declaration.
  class ParamDecl
    attr_reader :name, :value, :param_type, :raw_default

    def initialize(name, value, param_type, raw_default: nil)
      @name      = name
      @value     = value
      @param_type = param_type
      @raw_default = raw_default
    end
  end

  # Represents a local wire / logic / reg signal declaration.
  class LocalDecl
    attr_reader :kind, :name, :width, :signed, :init, :reset_init, :packed_dims, :unpacked_dims

    def initialize(kind, signal, init: signal.init, reset_init: nil)
      @kind         = kind
      @name         = signal.name
      @width        = signal.width
      @signed       = signal.signed
      @init         = init
      @reset_init    = reset_init
      @packed_dims   = signal.packed_dims.dup
      @unpacked_dims = signal.unpacked_dims.dup
    end

    def sv_kind
      :logic
    end

    def resettable?
      !@reset_init.nil?
    end

    def append_dimensions!(packed: [], unpacked: [])
      @packed_dims.concat(packed)
      @unpacked_dims.concat(unpacked)
      self
    end
  end

  class ElaboratedModule
    attr_reader :name, :params, :ports, :locals, :stmts

    def initialize(name, params:, ports:, locals:, stmts:)
      @name   = name
      @params = params
      @ports  = ports
      @locals = locals
      @stmts  = stmts
    end
  end

  # Continuous assignment: assign <lhs> = <rhs>;
  AssignStmt     = Struct.new(:lhs, :rhs)
  NbAssign       = Struct.new(:lhs, :rhs)
  BlockingAssign = Struct.new(:lhs, :rhs)

  class AlwaysFF
    attr_reader :body, :sensitivity, :clock, :reset

    def initialize(body, sensitivity: nil, clock: nil, reset: nil)
      @body        = body
      @sensitivity = sensitivity
      @clock       = clock
      @reset       = reset
    end

    def domain_driven?
      !@clock.nil? && !@reset.nil?
    end
  end

  AlwaysLatch = Struct.new(:body)
  AlwaysComb = Struct.new(:body)
  ForStmt = Struct.new(:index_name, :limit, :body)

  # Procedural if / else-if / else statement.
  class IfStmt
    attr_reader :cond, :then_stmts, :elsif_clauses, :else_stmts

    def initialize(cond, then_stmts)
      @cond         = cond
      @then_stmts    = then_stmts
      @elsif_clauses = []   # Array of { cond:, stmts: }
      @else_stmts    = nil
    end

    def add_elsif(cond, stmts)
      @elsif_clauses << { cond: cond, stmts: stmts }
    end

    def set_else(stmts)
      @else_stmts = stmts
    end
  end

  # Module instantiation.
  class Instance
    attr_reader :module_name, :inst_name, :params, :connections

    def initialize(module_name, inst_name, params:, connections:)
      @module_name  = module_name
      @inst_name    = inst_name
      @params      = params
      @connections = connections
    end
  end

  def self.normalize_signal_spec(signal)
    return signal if signal.is_a?(SignalSpec)

    raise TypeError, "signal declaration expects RSV::SignalSpec, got #{signal.class}"
  end

  def self.normalize_data_type(data_type)
    return data_type if data_type.is_a?(DataType)

    raise TypeError, "data type declaration expects RSV::DataType, got #{data_type.class}"
  end

  def self.normalize_expr(operand)
    case operand
    when SignalHandler, RawExpr, LiteralExpr, BinaryExpr, UnaryExpr, IndexExpr,
         RangeSelectExpr, IndexedPartSelectExpr, AsSintExpr, ClockSignal, ResetSignal,
         ParenExpr,
         MuxExpr, CatExpr, FillExpr, PackedCollectionExpr
      operand
    when String
      RawExpr.new(operand)
    when Numeric
      LiteralExpr.new(operand)
    else
      raise TypeError, "signal operand expects String, Numeric, RSV::SignalHandler, or RSV expression, got #{operand.class}"
    end
  end

  class << self
    alias normalize_operand normalize_expr
  end

  def self.binary_expr_width(op, lhs_width, rhs_width)
    case op
    when :<, :<=, :>, :>=, :==, :!=, :logic_and, :logic_or
      1
    when :+, :-, :*, :/, :%, :<<, :>>, :&, :|, :^
      [lhs_width, rhs_width].compact.max
    else
      [lhs_width, rhs_width].compact.max
    end
  end

  def self.infer_expr_width(expr)
    expr = normalize_expr(expr)

    case expr
    when SignalHandler, ClockSignal, ResetSignal
      flatten_packed_width(expr.width, expr.packed_dims)
    when RawExpr
      nil
    when LiteralExpr
      expr.width
    when BinaryExpr
      lhs_width = infer_expr_width(expr.lhs)
      rhs_width = infer_expr_width(expr.rhs)
      binary_expr_width(expr.op, lhs_width, rhs_width)
    when UnaryExpr
      unary_expr_width(expr)
    when ParenExpr
      expr.width
    when IndexExpr
      expr.width
    when RangeSelectExpr, IndexedPartSelectExpr
      expr.width
    when AsSintExpr
      expr.width
    when MuxExpr
      expr.width
    when CatExpr
      expr.width
    when FillExpr
      expr.width
    when PackedCollectionExpr
      flatten_packed_width(expr.width, expr.packed_dims)
    else
      nil
    end
  end

  def self.unary_expr_width(expr)
    case expr.op
    when :!, :reduce_or, :reduce_and
      1
    when :~
      infer_expr_width(expr.operand)
    else
      infer_expr_width(expr.operand)
    end
  end

  def self.reset_init_expr(init, width)
    if init.is_a?(DataType)
      raise ArgumentError, "reset initializer data type must include a scalar init value" if init.init.nil?

      return reset_init_expr(init.init, width)
    end

    return normalize_expr(init) if init.is_a?(String)

    LiteralExpr.new(init, width: width, format: :hex)
  end

  def self.shape_matches_type?(type, init)
    return true unless init.is_a?(DataType)

    type.width == init.width &&
      dims_match?(type.packed_dims, init.packed_dims) &&
      dims_match?(type.unpacked_dims, init.unpacked_dims)
  end

  def self.shape_dims(type_or_signal)
    [
      type_or_signal.respond_to?(:packed_dims) ? type_or_signal.packed_dims : [],
      type_or_signal.respond_to?(:unpacked_dims) ? type_or_signal.unpacked_dims : []
    ]
  end

  def self.dims_match?(lhs_dims, rhs_dims)
    return false unless lhs_dims.length == rhs_dims.length

    lhs_dims.zip(rhs_dims).all? do |lhs_dim, rhs_dim|
      dimension_key(lhs_dim) == dimension_key(rhs_dim)
    end
  end

  def self.dimension_key(dim)
    dim = normalize_expr(dim)

    case dim
    when LiteralExpr
      [:literal, dim.value]
    when RawExpr
      [:raw, dim.source]
    when SignalHandler
      [:signal, dim.name]
    else
      [dim.class.name, dim.to_s]
    end
  end

  def self.with_procedural_builder(builder)
    stack = Thread.current[:rsv_procedural_builders] ||= []
    stack << builder
    yield
  ensure
    stack.pop
  end

  def self.current_procedural_builder
    stack = Thread.current[:rsv_procedural_builders]
    stack&.last
  end

  def self.with_module_def(mod)
    stack = Thread.current[:rsv_module_defs] ||= []
    stack << mod
    yield
  ensure
    stack.pop
  end

  def self.current_module_def
    stack = Thread.current[:rsv_module_defs]
    stack&.last
  end

  def self.expr_packed_dims(expr)
    expr = normalize_expr(expr)
    expr.respond_to?(:packed_dims) ? expr.packed_dims : []
  end

  def self.expr_signed(expr)
    expr = normalize_expr(expr)
    expr.respond_to?(:signed) ? expr.signed : false
  end

  def self.expr_unpacked_dims(expr)
    expr = normalize_expr(expr)
    expr.respond_to?(:unpacked_dims) ? expr.unpacked_dims : []
  end

  def self.expr_shape_signature(expr)
    expr = normalize_expr(expr)
    [
      element_width(expr),
      expr_signed(expr),
      expr_packed_dims(expr).map { |dim| dimension_key(dim) },
      expr_unpacked_dims(expr).map { |dim| dimension_key(dim) }
    ]
  end

  def self.index_only_expr?(expr)
    !expr_packed_dims(expr).empty? || !expr_unpacked_dims(expr).empty?
  end

  def self.validate_index(idx)
    case idx
    when Integer
      return
    when SignalHandler
      raise ArgumentError, "array/memory index must be unsigned (uint), got signed signal" if idx.signed
      return
    when IndexExpr, RangeSelectExpr, IndexedPartSelectExpr, BinaryExpr, UnaryExpr, RawExpr, LiteralExpr
      return
    else
      raise ArgumentError, "array/memory index must be a hardware uint or an integer literal, got #{idx.class}"
    end
  end

  def self.element_width(expr)
    expr = normalize_expr(expr)
    return expr.element_width if expr.respond_to?(:element_width)
    return expr.width if expr.respond_to?(:width)

    nil
  end

  def self.flatten_packed_width(width, packed_dims)
    return width if packed_dims.empty?
    return nil unless width.is_a?(Integer)

    total = width
    packed_dims.each do |dim|
      value = dimension_value(dim)
      return nil unless value.is_a?(Integer)

      total *= value
    end
    total
  end

  def self.dimension_value(dim)
    dim = normalize_expr(dim)

    case dim
    when LiteralExpr
      dim.value
    else
      nil
    end
  end
end
