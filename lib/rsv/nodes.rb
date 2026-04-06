# frozen_string_literal: true

module RSV
  # ════════════════════════════════════════════════════════════════════════════
  # Expression operator mixins
  # ════════════════════════════════════════════════════════════════════════════

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

  # ════════════════════════════════════════════════════════════════════════════
  # Assignment operators (<= / >=)
  # ════════════════════════════════════════════════════════════════════════════

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

  # ════════════════════════════════════════════════════════════════════════════
  # Data types and type factories
  # ════════════════════════════════════════════════════════════════════════════

  class DataTypeFactory
    def initialize(module_def, storage)
      @module_def = module_def
      @storage = storage
    end

    def fill(*dims_and_type)
      @module_def.send(:compose_data_type, *dims_and_type)
    end
  end

  # Anonymous RSV data type used to define named hardware objects.
  # Non-hardware DataType instances with init values support Ruby-time arithmetic.
  class DataType
    attr_reader :width, :signed, :init, :unpacked_dims, :bundle_type

    def initialize(width:, signed: false, init: nil, unpacked_dims: [], bundle_type: nil, **_kw)
      @width = width
      @signed = signed
      @init = init
      @unpacked_dims = unpacked_dims.dup
      @bundle_type = bundle_type
    end

    def append_dimensions(unpacked: [], **_kw)
      DataType.new(
        width: @width,
        signed: @signed,
        init: @init,
        unpacked_dims: @unpacked_dims + unpacked,
        bundle_type: @bundle_type
      )
    end

    def as_sint
      AsSintExpr.new(self)
    end

    def scalar?
      @unpacked_dims.empty? && @width.is_a?(Integer) && !@init.nil? && @init.is_a?(Integer)
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

  # ════════════════════════════════════════════════════════════════════════════
  # Expression nodes
  # ════════════════════════════════════════════════════════════════════════════

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
    include HandlerDelegation

    attr_reader :handler, :negated

    def initialize(handler, negated: false)
      @handler = handler
      @negated = negated
    end

    def neg
      ClockSignal.new(@handler, negated: true)
    end
  end

  # Reset type marker for negedge / active-low support.
  class ResetSignal
    include ExprOps
    include AssignableExpr
    include HandlerDelegation

    attr_reader :handler, :negated

    def initialize(handler, negated: false)
      @handler = handler
      @negated = negated
    end

    def neg
      ResetSignal.new(@handler, negated: true)
    end
  end

  # Bit concatenation: {a, b, c}
  class CatExpr
    include ExprOps

    attr_reader :parts

    def initialize(parts)
      expanded = parts.flat_map do |p|
        if p.is_a?(BundleSignalGroup)
          p.as_uint.parts
        elsif p.is_a?(SignalHandler) && !p.unpacked_dims.empty?
          p.as_uint.parts
        else
          [RSV.normalize_expr(p)]
        end
      end
      @parts = expanded
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

  # Intermediate expression returned by mux1h(); expanded to MuxCaseStmt on assignment.
  class Mux1hExpr
    attr_reader :sel, :dats

    def initialize(sel, dats)
      @sel  = sel
      @dats = dats
    end
  end

  # Intermediate expression returned by muxp(); expanded to MuxCaseStmt on assignment.
  class MuxpExpr
    attr_reader :sel, :dats, :lsb_first

    def initialize(sel, dats, lsb_first: true)
      @sel       = sel
      @dats      = dats
      @lsb_first = lsb_first
    end
  end

  # Intermediate expression returned by pop_count(); expanded to PopCountStmt on assignment.
  class PopCountExpr
    attr_reader :vec, :in_width, :out_width

    def initialize(vec)
      normalized = RSV.normalize_expr(vec)
      @vec = normalized
      w = RSV.infer_expr_width(normalized)
      raise ArgumentError, "pop_count requires a signal with known integer width, got #{w.inspect}" unless w.is_a?(Integer)
      @in_width = w
      @out_width = RSV.log2ceil(w + 1)
    end
  end

  # Statement for pop_count — emits a for-loop accumulator.
  class PopCountStmt
    attr_reader :lhs, :vec, :in_width, :out_width

    def initialize(lhs, vec, in_width:, out_width:)
      @lhs = lhs
      @vec = vec
      @in_width = in_width
      @out_width = out_width
    end
  end

  # Statement for vec reverse — emits a for-loop reversal.
  class VecReverseStmt
    attr_reader :lhs, :src, :dim

    def initialize(lhs, src, dim:)
      @lhs = lhs
      @src = src
      @dim = dim
    end
  end

  # A single field inside a BundleDef with direction.
  BundleFieldDef = Struct.new(:name, :data_type, :dir, keyword_init: true)

  # Direction-decorated data type: output(uint(8)), input(uint(8))
  class DirectedType
    attr_reader :dir, :data_type

    def initialize(dir, data_type)
      @dir = dir
      @data_type = data_type
    end
  end

  # Flipped bundle type: all field directions reversed
  class FlippedType
    attr_reader :data_type

    def initialize(data_type)
      @data_type = data_type
    end
  end

  # Wire type descriptor: wire(uint(8)) — for use with let
  class WireType
    attr_reader :data_type, :init

    def initialize(data_type, init: nil)
      @data_type = data_type
      @init = init
    end
  end

  # Reg type descriptor: reg(uint(16), init: 0x15) — for use with let
  class RegType
    attr_reader :data_type, :init

    def initialize(data_type, init: nil)
      @data_type = data_type
      @init = init
    end
  end

  # Const type descriptor: const(uint(8, 42)) — for use with let
  class ConstType
    attr_reader :data_type

    def initialize(data_type)
      @data_type = data_type
    end
  end

  # Expr type descriptor: expr(a + b) — for use with let
  class ExprType
    attr_reader :rhs, :width, :signed

    def initialize(rhs, width: nil, signed: false)
      @rhs = rhs
      @width = width
      @signed = signed
    end
  end

  # Expression node for accessing a field of a bundle-typed signal: base.field_name
  class FieldAccessExpr
    include ExprOps
    include AssignableExpr

    attr_reader :base, :field_name

    def initialize(base, field_name)
      @base = base
      @field_name = field_name
    end

    def to_s
      "#{@base}.#{@field_name}"
    end

    def base_name
      @base.respond_to?(:base_name) ? @base.base_name : @base.to_s
    end
  end

  # Holds flattened child signals for a bundle-typed declaration.
  # Supports field access via method_missing and whole-bundle assignment.
  class BundleSignalGroup
    include AssignableExpr

    attr_reader :name, :bundle_type, :children, :unpacked_dims

    # children: Hash { field_name => SignalHandler | BundleSignalGroup }
    def initialize(name, bundle_type:, children:, unpacked_dims: [])
      @name = name
      @bundle_type = bundle_type
      @children = children
      @unpacked_dims = unpacked_dims
    end

    def <=(rhs)
      if rhs.is_a?(BundleSignalGroup)
        @children.each do |fname, child|
          rhs_child = rhs.children[fname]
          raise ArgumentError, "bundle field mismatch: #{fname}" unless rhs_child
          child <= rhs_child
        end
      elsif rhs.is_a?(IndexedBundleSignalGroup)
        @children.each do |fname, child|
          rhs_child = rhs.send(fname.to_sym)
          child <= rhs_child
        end
      else
        super
      end
    end

    def >=(lhs)
      if lhs.is_a?(BundleSignalGroup)
        lhs <= self
      else
        super
      end
    end

    def [](idx)
      IndexedBundleSignalGroup.new(self, RSV.normalize_expr(idx))
    end

    def method_missing(meth, *args, &blk)
      field_name = meth.to_s
      if args.empty? && blk.nil? && @children.key?(field_name)
        return @children[field_name]
      end
      super
    end

    def respond_to_missing?(meth, include_private = false)
      @children.key?(meth.to_s) || super
    end

    # Collect all leaf SignalHandlers recursively.
    def leaf_handlers
      @children.each_value.flat_map do |child|
        child.is_a?(BundleSignalGroup) ? child.leaf_handlers : [child]
      end
    end

    # Total bit width of all leaf fields including unpacked dimensions.
    def get_width
      base = leaf_handlers.sum { |h| h.width }
      @unpacked_dims.each { |d| base *= RSV.dimension_value(d) }
      base
    end

    # Concatenate all leaf fields into a uint expression.
    # First-declared field at MSB, last-declared at LSB.
    # For vec(N, bundle), produces nested concatenations per element.
    def as_uint
      leaves = leaf_handlers
      if @unpacked_dims.empty?
        CatExpr.new(leaves)
      else
        dim = RSV.dimension_value(@unpacked_dims.first)
        parts = (dim - 1).downto(0).map do |i|
          idx = LiteralExpr.new(i)
          CatExpr.new(leaves.map { |h| IndexExpr.new(h, idx) })
        end
        CatExpr.new(parts)
      end
    end

    # Create a reversed copy of a vec(N, bundle) signal.
    def reverse
      raise ArgumentError, "reverse requires a vec bundle signal" if @unpacked_dims.empty?
      mod = RSV.current_module_def
      raise ArgumentError, "reverse requires a module context" unless mod
      mod.send(:expand_bundle_reverse, self)
    end

    # Convert to target type via flatten→width-adjust→reshape.
    def as_type(target_type)
      target = RSV.normalize_data_type(target_type)
      src_flat = as_uint
      src_width = get_width
      RSV.reshape_to_type(src_flat, src_width, target, @name)
    end

    def to_s
      @name
    end
  end

  # Result of indexing a BundleSignalGroup (e.g., fifo[i]).
  # Routes field access to IndexExpr on the child handler.
  class IndexedBundleSignalGroup
    include AssignableExpr

    attr_reader :group, :index

    def initialize(group, index)
      @group = group
      @index = index
    end

    def <=(rhs)
      if rhs.is_a?(BundleSignalGroup) || rhs.is_a?(IndexedBundleSignalGroup)
        @group.children.each do |fname, child|
          lhs_indexed = IndexExpr.new(child, @index)
          rhs_child = rhs.is_a?(BundleSignalGroup) ? rhs.children[fname] : rhs.send(fname.to_sym)
          lhs_indexed <= rhs_child
        end
      else
        super
      end
    end

    def >=(lhs)
      if lhs.is_a?(BundleSignalGroup) || lhs.is_a?(IndexedBundleSignalGroup)
        lhs <= self
      else
        super
      end
    end

    def [](idx)
      raise ArgumentError, "cannot double-index a bundle signal group"
    end

    def method_missing(meth, *args, &blk)
      field_name = meth.to_s
      if args.empty? && blk.nil? && @group.children.key?(field_name)
        child = @group.children[field_name]
        if child.is_a?(BundleSignalGroup)
          # Nested bundle in vec: index propagates
          indexed_children = child.children.transform_values do |c|
            IndexExpr.new(c, @index)
          end
          return BundleSignalGroup.new(
            "#{child.name}[#{@index}]",
            bundle_type: child.bundle_type,
            children: indexed_children
          )
        else
          return IndexExpr.new(child, @index)
        end
      end
      super
    end

    def respond_to_missing?(meth, include_private = false)
      @group.children.key?(meth.to_s) || super
    end

    def to_s
      "#{@group.name}[#{@index}]"
    end
  end

  # Internal named signal declaration spec used by ports/locals.
  class SignalSpec
    attr_reader :name, :width, :signed, :init, :unpacked_dims, :bundle_type

    def initialize(name, width:, signed: false, init: nil, unpacked_dims: [], bundle_type: nil, **_kw)
      @name         = name
      @width        = width
      @signed       = signed
      @init         = init
      @unpacked_dims = unpacked_dims.dup
      @bundle_type  = bundle_type
    end

    def append_dimensions!(unpacked: [], **_kw)
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

    attr_reader :base, :index, :unpacked_dims

    def initialize(base, index)
      @base = RSV.normalize_expr(base)
      @index = RSV.normalize_expr(index)
      @unpacked_dims = RSV.expr_unpacked_dims(@base).dup
      @element_width = RSV.element_width(@base)

      if !@unpacked_dims.empty?
        @unpacked_dims = @unpacked_dims.drop(1)
      else
        @element_width = 1
      end
    end

    def width
      @element_width
    end

    def element_width
      @element_width
    end

    def base_name
      @base.base_name if @base.respond_to?(:base_name)
    end

    def bundle_type
      @base.respond_to?(:bundle_type) ? @base.bundle_type : nil
    end

    def method_missing(meth, *args, &blk)
      bt = bundle_type
      if bt && args.empty? && blk.nil?
        field_name = meth.to_s
        fd = bt.fields.find { |f| f.name == field_name }
        return FieldAccessExpr.new(self, field_name) if fd
      end
      super
    end

    def respond_to_missing?(meth, include_private = false)
      bt = bundle_type
      return true if bt && bt.fields.any? { |f| f.name == meth.to_s }
      super
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

    attr_reader :parts_low_to_high, :width, :signed, :unpacked_dims

    def initialize(parts_low_to_high, width:, signed: false, unpacked_dims: [], **_kw)
      @parts_low_to_high = parts_low_to_high.map { |part| RSV.normalize_expr(part) }
      @width = width
      @signed = signed
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

      entries = if !unpacked_dims.empty?
        build_unpacked_entries(expr, unpacked_dims.first)
      else
        build_scalar_entries(expr)
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
        raise ArgumentError, "sv_map results must all have the same shape"
      end

      unpacked_dims = RSV.expr_unpacked_dims(first)
      unless unpacked_dims.empty?
        raise ArgumentError, "sv_map phase 1 only supports scalar result shapes"
      end

      PackedCollectionExpr.new(
        mapped,
        width: RSV.element_width(first),
        signed: RSV.expr_signed(first),
        unpacked_dims: [mapped.length]
      )
    end
  end

  # ════════════════════════════════════════════════════════════════════════════
  # Signal handlers — opaque handles for hardware signals
  # ════════════════════════════════════════════════════════════════════════════

  # Opaque handle returned from declarations and used to reference a signal.
  class SignalHandler
    include ExprOps
    include AssignableExpr

    attr_reader :name, :width, :signed, :kind, :init, :unpacked_dims, :bundle_type

    def initialize(name, width: 1, signed: false, kind: nil, init: nil, unpacked_dims: [], bundle_type: nil, **_kw)
      @name         = name
      @width        = width
      @signed       = signed
      @kind         = kind
      @init         = init
      @unpacked_dims = unpacked_dims.dup
      @bundle_type  = bundle_type
    end

    def with_width(width)
      SignalHandler.new(
        @name,
        width: width,
        signed: @signed,
        kind: @kind,
        init: @init,
        unpacked_dims: @unpacked_dims,
        bundle_type: @bundle_type
      )
    end

    def append_dimensions!(unpacked: [], **_kw)
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

    # Concatenate vec elements into a uint expression.
    # Highest index at MSB, index 0 at LSB.
    def as_uint
      raise ArgumentError, "as_uint requires a vec signal" if @unpacked_dims.empty?
      dim = RSV.dimension_value(@unpacked_dims.first)
      parts = (dim - 1).downto(0).map do |i|
        IndexExpr.new(self, LiteralExpr.new(i))
      end
      CatExpr.new(parts)
    end

    # Total bit width including all unpacked dimensions.
    def get_width
      total = @width
      @unpacked_dims.each { |d| total *= RSV.dimension_value(d) }
      total
    end

    # Create a reversed copy of a vec signal.
    def reverse
      raise ArgumentError, "reverse requires a vec signal" if @unpacked_dims.empty?
      mod = RSV.current_module_def
      raise ArgumentError, "reverse requires a module context" unless mod
      mod.send(:expand_vec_reverse, self)
    end

    # Convert to target type via flatten→width-adjust→reshape.
    def as_type(target_type)
      target = RSV.normalize_data_type(target_type)
      if @unpacked_dims.empty?
        src_flat = self
        src_width = @width
      else
        src_flat = as_uint
        src_width = get_width
      end
      RSV.reshape_to_type(src_flat, src_width, target, @name)
    end

    def method_missing(meth, *args, &blk)
      if @bundle_type && args.empty? && blk.nil?
        field_name = meth.to_s
        fd = @bundle_type.fields.find { |f| f.name == field_name }
        if fd
          return FieldAccessExpr.new(self, field_name)
        end
      end
      super
    end

    def respond_to_missing?(meth, include_private = false)
      if @bundle_type
        return true if @bundle_type.fields.any? { |f| f.name == meth.to_s }
      end
      super
    end
  end

  class InstancePortHandler
    include ExprOps
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

    def width
      @port.width
    end

    def signed
      @port.signed
    end

    def unpacked_dims
      @port.unpacked_dims
    end

    def element_width
      @port.width
    end

    def base_name
      "#{@instance_handle.inst_name}_#{@port.name}"
    end

    def to_s
      @port.name
    end
  end

  class ModuleDefinitionHandle
    attr_reader :definition, :params, :ports

    def initialize(definition)
      @definition = definition
      @module_name = definition.respond_to?(:module_name) ? definition.module_name : definition.name
      @params = definition.params
      @ports = definition.ports
    end

    def module_name
      @module_name
    end

    alias name module_name

    def to_sv(output = nil)
      raise ArgumentError, "module definition handle does not support to_sv" unless @definition.respond_to?(:to_sv)

      @definition.to_sv(output)
    end
  end

  class ModuleInstanceHandle
    attr_reader :definition, :definition_handle, :inst_name, :params, :connections

    def initialize(definition, inst_name:, param_overrides: {})
      @definition_handle = RSV.normalize_module_definition_handle(definition)
      @definition = @definition_handle.definition
      @inst_name = inst_name
      @params = @definition_handle.params.each_with_object({}) do |param, memo|
        key_str = param.name.to_s
        key_sym = param.name.to_sym
        memo[param.name] = param_overrides.fetch(key_sym, param_overrides.fetch(key_str, param.value))
      end
      @connections = {}
      @ports = @definition_handle.ports.each_with_object({}) do |port, memo|
        memo[port.name] = InstancePortHandler.new(self, port)
      end
    end

    def module_name
      @definition_handle.module_name
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

  # ════════════════════════════════════════════════════════════════════════════
  # Declaration nodes — ports, locals, constants, parameters
  # ════════════════════════════════════════════════════════════════════════════

  # Represents an input / output / inout port declaration.
  class PortDecl
    attr_reader :dir, :name, :width, :signed, :unpacked_dims, :raw_type, :attr

    def initialize(dir, signal, raw_type: nil, attr: nil)
      @dir          = dir    # :input | :output | :inout
      @name         = signal.name
      @width        = signal.width  # Integer or String (e.g. "WIDTH")
      @signed       = signal.signed
      @unpacked_dims = signal.unpacked_dims.dup
      @raw_type      = raw_type
      @attr          = attr  # Hash or nil: { "mark_debug" => "true" } or { "keep" => nil }
    end

    def append_dimensions!(unpacked: [], **_kw)
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

  # Represents a localparam constant declaration.
  class ConstDecl
    attr_reader :name, :width, :signed, :init, :unpacked_dims, :attr

    def initialize(signal, init:, attr: nil)
      @name         = signal.name
      @width        = signal.width
      @signed       = signal.signed
      @init         = init
      @unpacked_dims = signal.unpacked_dims.dup
      @attr          = attr
    end

    def sv_kind
      :localparam
    end
  end

  # Represents a local wire / logic / reg signal declaration.
  class LocalDecl
    attr_reader :kind, :name, :width, :signed, :init, :reset_init, :unpacked_dims, :attr

    def initialize(kind, signal, init: signal.init, reset_init: nil, attr: nil)
      @kind         = kind
      @name         = signal.name
      @width        = signal.width
      @signed       = signal.signed
      @init         = init
      @reset_init    = reset_init
      @unpacked_dims = signal.unpacked_dims.dup
      @attr          = attr
    end

    def sv_kind
      :logic
    end

    def resettable?
      !@reset_init.nil?
    end

    def append_dimensions!(unpacked: [], **_kw)
      @unpacked_dims.concat(unpacked)
      self
    end
  end

  # ════════════════════════════════════════════════════════════════════════════
  # Elaborated (flattened) output structures
  # ════════════════════════════════════════════════════════════════════════════

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

  class ElaboratedBundle
    attr_reader :name, :params, :fields

    def initialize(name, params:, fields:)
      @name   = name
      @params = params
      @fields = fields
    end
  end

  # ════════════════════════════════════════════════════════════════════════════
  # Statement nodes — assignments, always blocks, control flow, instances
  # ════════════════════════════════════════════════════════════════════════════

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
  # qualifier: nil, :unique, or :priority
  class IfStmt
    attr_reader :cond, :then_stmts, :elsif_clauses, :else_stmts, :qualifier

    def initialize(cond, then_stmts, qualifier: nil)
      @cond         = cond
      @then_stmts    = then_stmts
      @elsif_clauses = []   # Array of { cond:, stmts: }
      @else_stmts    = nil
      @qualifier     = qualifier
    end

    def add_elsif(cond, stmts)
      @elsif_clauses << { cond: cond, stmts: stmts }
    end

    def set_else(stmts)
      @else_stmts = stmts
    end
  end

  # Procedural case/casez/casex statement.
  # case_kind: :case, :casez, :casex
  # qualifier: nil, :unique, :priority
  # branches: Array of { vals: [expr, ...], stmts: [...] }
  # default_stmts: nil or [...]
  class CaseStmt
    attr_reader :expr, :case_kind, :qualifier, :branches, :default_stmts

    def initialize(expr, case_kind:, qualifier: nil)
      @expr          = expr
      @case_kind     = case_kind
      @qualifier     = qualifier
      @branches      = []
      @default_stmts = nil
    end

    def add_branch(vals, stmts)
      @branches << { vals: vals, stmts: stmts }
    end

    def set_default(stmts)
      @default_stmts = stmts
    end
  end

  # Module instantiation.
  class Instance
    attr_reader :module_name, :inst_name, :params, :connections, :port_names

    def initialize(module_name, inst_name, params:, connections:, port_names: nil)
      @module_name  = module_name
      @inst_name    = inst_name
      @params      = params
      @connections = connections
      @port_names  = port_names
    end
  end

  # Preprocessor directive nodes
  SvDefine     = Struct.new(:macro_name, :value)
  SvUndef      = Struct.new(:macro_name)
  SvIfdef      = Struct.new(:macro_name, :body, :elsif_clauses, :else_body)
  SvIfndef     = Struct.new(:macro_name, :body, :elsif_clauses, :else_body)

  # Inline SystemVerilog code fragment
  SvPlugin     = Struct.new(:code)

  # ════════════════════════════════════════════════════════════════════════════
  # Macro, generate, and parameter reference nodes
  # ════════════════════════════════════════════════════════════════════════════

  # Expression that references a macro value: `MACRO_NAME
  class MacroRef
    include ExprOps
    attr_reader :macro_name

    def initialize(macro_name)
      @macro_name = macro_name
    end

    def width
      nil
    end
  end

  # Generate block nodes
  class GenerateIf
    attr_reader :cond, :label, :locals, :stmts, :elsif_clauses, :else_body

    def initialize(cond, label:, locals:, stmts:, elsif_clauses: [], else_body: nil)
      @cond           = cond
      @label          = label
      @locals         = locals
      @stmts          = stmts
      @elsif_clauses  = elsif_clauses  # Array of { cond:, label:, locals:, stmts: }
      @else_body      = else_body      # { label:, locals:, stmts: } or nil
    end

    def add_elsif(cond, label:, locals:, stmts:)
      @elsif_clauses << { cond: cond, label: label, locals: locals, stmts: stmts }
    end

    def set_else(label:, locals:, stmts:)
      @else_body = { label: label, locals: locals, stmts: stmts }
    end
  end

  class GenerateFor
    attr_reader :genvar, :start_val, :end_val, :label, :locals, :stmts

    def initialize(genvar, start_val, end_val, label:, locals:, stmts:)
      @genvar    = genvar
      @start_val = start_val
      @end_val   = end_val
      @label     = label
      @locals    = locals
      @stmts     = stmts
    end
  end

  # Genvar reference expression: usable inside generate for
  class GenvarRef
    include ExprOps

    attr_reader :name

    def initialize(name)
      @name = name
    end

    def width
      nil
    end
  end

  # SV parameter reference expression: usable in types and expressions
  class SvParamRef
    include ExprOps

    attr_reader :name

    def initialize(name)
      @name = name
    end

    def width
      nil
    end

    def to_s
      @name
    end
  end

  # ════════════════════════════════════════════════════════════════════════════
  # Module-level utility methods
  # ════════════════════════════════════════════════════════════════════════════

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
    when SignalHandler, InstancePortHandler, RawExpr, LiteralExpr, BinaryExpr, UnaryExpr, IndexExpr,
         RangeSelectExpr, IndexedPartSelectExpr, AsSintExpr, ClockSignal, ResetSignal,
         ParenExpr, FieldAccessExpr,
         MuxExpr, CatExpr, FillExpr, PackedCollectionExpr, MacroRef, GenvarRef, SvParamRef
      operand
    when String
      RawExpr.new(operand)
    when Numeric
      LiteralExpr.new(operand)
    else
      raise TypeError, "signal operand expects String, Numeric, RSV::SignalHandler, or RSV expression, got #{operand.class}"
    end
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
    when SignalHandler, InstancePortHandler, ClockSignal, ResetSignal
      expr.width
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
      expr.width
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
      dims_match?(type.unpacked_dims, init.unpacked_dims)
  end

  def self.shape_dims(type_or_signal)
    [
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

  def self.contains_instance_port?(expr)
    expr = normalize_expr(expr)

    case expr
    when InstancePortHandler
      true
    when IndexExpr
      contains_instance_port?(expr.base) || contains_instance_port?(expr.index)
    when RangeSelectExpr
      contains_instance_port?(expr.base) || contains_instance_port?(expr.msb) || contains_instance_port?(expr.lsb)
    when IndexedPartSelectExpr
      contains_instance_port?(expr.base) || contains_instance_port?(expr.start) || contains_instance_port?(expr.part_width)
    when BinaryExpr
      contains_instance_port?(expr.lhs) || contains_instance_port?(expr.rhs)
    when UnaryExpr
      contains_instance_port?(expr.operand)
    when ParenExpr
      contains_instance_port?(expr.inner)
    when AsSintExpr
      contains_instance_port?(expr.operand)
    when MuxExpr
      contains_instance_port?(expr.sel) || contains_instance_port?(expr.a) || contains_instance_port?(expr.b)
    when CatExpr
      expr.parts.any? { |part| contains_instance_port?(part) }
    when FillExpr
      contains_instance_port?(expr.count) || contains_instance_port?(expr.part)
    when PackedCollectionExpr
      expr.parts_low_to_high.any? { |part| contains_instance_port?(part) }
    else
      false
    end
  end

  def self.normalize_module_definition_handle(source)
    return source if source.is_a?(ModuleDefinitionHandle)

    if source.respond_to?(:params) && source.respond_to?(:ports) && (source.respond_to?(:module_name) || source.respond_to?(:name))
      return ModuleDefinitionHandle.new(source)
    end

    raise TypeError, "module definition expects an elaborated module or a definition handle"
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
      expr_unpacked_dims(expr).map { |dim| dimension_key(dim) }
    ]
  end

  def self.index_only_expr?(expr)
    !expr_unpacked_dims(expr).empty?
  end

  def self.validate_index(idx)
    case idx
    when Integer
      return
    when SignalHandler
      raise ArgumentError, "array/memory index must be unsigned (uint), got signed signal" if idx.signed
      return
    when IndexExpr, RangeSelectExpr, IndexedPartSelectExpr, BinaryExpr, UnaryExpr, RawExpr, LiteralExpr, GenvarRef, SvParamRef
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

  def self.dimension_value(dim)
    dim = normalize_expr(dim)

    case dim
    when LiteralExpr
      dim.value
    else
      nil
    end
  end

  def self.format_dim(d)
    case d
    when Integer then d.to_s
    when LiteralExpr then d.value.to_s
    else d.to_s
    end
  end

  # ceil(log2(n)) — returns minimum bits to address n items.
  def self.log2ceil(n)
    raise ArgumentError, "log2ceil requires positive integer, got #{n}" unless n.is_a?(Integer) && n > 0
    return 0 if n == 1
    (n - 1).bit_length
  end

  # Compute total flat bit width of a DataType.
  def self.type_total_width(dt)
    base = dt.width
    return nil unless base.is_a?(Integer)
    dt.unpacked_dims.each { |d| base *= dimension_value(d) }
    base
  end

  # Core as_type: flatten source → adjust width → reshape to target.
  # For scalar targets returns expression; for bundle/vec targets creates wires.
  def self.reshape_to_type(src_flat, src_width, target, name_hint)
    tgt_width = type_total_width(target)
    raise ArgumentError, "as_type target must have known width" unless tgt_width

    # Width adjustment
    adjusted = adjust_type_width(src_flat, src_width, tgt_width)

    # Reshape to target
    if target.bundle_type && target.unpacked_dims.empty?
      # → bundle: need module context to create wires
      mod = current_module_def
      raise ArgumentError, "as_type to bundle requires module context" unless mod
      mod.send(:expand_as_type_to_bundle, adjusted, target, name_hint)
    elsif !target.unpacked_dims.empty? && target.bundle_type
      # → vec(N, bundle): need module context
      mod = current_module_def
      raise ArgumentError, "as_type to vec(bundle) requires module context" unless mod
      mod.send(:expand_as_type_to_vec_bundle, adjusted, target, name_hint)
    elsif !target.unpacked_dims.empty?
      # → vec(N, scalar): need module context
      mod = current_module_def
      raise ArgumentError, "as_type to vec requires module context" unless mod
      mod.send(:expand_as_type_to_vec, adjusted, target, name_hint)
    elsif target.signed
      AsSintExpr.new(adjusted)
    else
      adjusted
    end
  end

  # Width adjustment: truncate or zero-extend.
  def self.adjust_type_width(src_expr, src_width, tgt_width)
    if src_width == tgt_width
      src_expr
    elsif src_width > tgt_width
      RangeSelectExpr.new(src_expr, tgt_width - 1, 0)
    else
      pad = tgt_width - src_width
      CatExpr.new([LiteralExpr.new(0, width: pad), src_expr])
    end
  end
end
