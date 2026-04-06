# frozen_string_literal: true

require "json"
require "open3"

module RSV
  class ImportedModuleDefinition
    attr_reader :name, :params, :ports

    def initialize(name, params, ports)
      @name = name
      @params = params
      @ports = ports
    end
  end

  class ImportedModule
    PYSLANG_HELPER = <<~'PY'
      import json
      import os
      import re
      import sys
      import tempfile

      import pyslang

      PROBE_MODULE = "__rsv_import_probe__"
      PROBE_INSTANCE = "__rsv_import_probe_inst__"
      IGNORED_DIAG_CODES = {
          "DiagCode(UnconnectedNamedPort)",
          "DiagCode(UnconnectedPositionalPort)"
      }

      def normalize_text(text):
          return re.sub(r"\s+", " ", text.strip())

      def node_text(node):
          if node is None:
              return None
          text = re.sub(r"^\s*=\s*", "", str(node), count=1)
          return normalize_text(text)

      def add_user_directories(source_manager, directories):
          seen = set()
          for directory in directories:
              if not directory:
                  continue
              directory = os.path.abspath(directory)
              if directory in seen:
                  continue
              source_manager.addUserDirectories(directory)
              seen.add(directory)

      def escape_include_path(path):
          return path.replace("\\", "\\\\").replace("\"", "\\\"")

      def define_line(name, value):
          if value in (None, "", True):
              return f"`define {name}"
          return f"`define {name} {value}"

      def wrapper_source(files, top, param_overrides, defines):
          lines = []
          for name, value in defines.items():
              lines.append(define_line(name, value))
          for path in files:
              lines.append(f"`include \"{escape_include_path(path)}\"")
          if param_overrides:
              assignments = ", ".join(
                  f".{name}({value})" for name, value in param_overrides.items()
              )
              instantiation = f"{top} #({assignments}) {PROBE_INSTANCE}();"
          else:
              instantiation = f"{top} {PROBE_INSTANCE}();"
          lines.append(f"module {PROBE_MODULE};")
          lines.append(f"  {instantiation}")
          lines.append("endmodule")
          return "\n".join(lines) + "\n"

      def summarize_diagnostics(diags):
          entries = []
          for diag in diags:
              code = str(diag.code)
              if code in IGNORED_DIAG_CODES:
                  continue
              if not getattr(diag, "isError", False):
                  continue
              entries.append(f"{code} at {diag.location}")
          return entries

      def find_module_syntax(tree, module_name):
          for member in tree.root.members:
              header = getattr(member, "header", None)
              name = getattr(header, "name", None)
              if name is not None and normalize_text(str(name)) == module_name:
                  return member
          raise RuntimeError(f"module {module_name} not found in parsed syntax tree")

      def find_probe_instance(compilation):
          for top_instance in compilation.getRoot().topInstances:
              if normalize_text(str(top_instance.body.name)) != PROBE_MODULE:
                  continue
              instance_symbol = top_instance.body.find(PROBE_INSTANCE)
              if instance_symbol is not None:
                  return instance_symbol
          raise RuntimeError(f"probe module {PROBE_MODULE} was not elaborated")

      def normalize_direction(direction_text):
          direction = normalize_text(direction_text).lower()
          mapping = {
              "input": "input",
              "output": "output",
              "inout": "inout",
              "ref": "inout",
              "argumentdirection.in": "input",
              "argumentdirection.out": "output",
              "argumentdirection.inout": "inout",
              "argumentdirection.ref": "inout"
          }
          if direction not in mapping:
              raise RuntimeError(f"unsupported port direction: {direction_text}")
          return mapping[direction]

      def port_raw_type(port_syntax):
          header = getattr(port_syntax, "header", None)
          declarator = getattr(port_syntax, "declarator", None)
          parts = []
          if header is not None:
              data_type_text = node_text(getattr(header, "dataType", None))
              if data_type_text:
                  parts.append(data_type_text)
          if declarator is not None:
              for dim in getattr(declarator, "dimensions", []):
                  if not hasattr(dim, "kind"):
                      continue
                  dim_text = node_text(dim)
                  if dim_text:
                      parts.append(dim_text)
          if not parts:
              return None
          return normalize_text(" ".join(parts))

      def collect_syntax_parameters(module_syntax):
          param_list = getattr(module_syntax.header, "parameters", None)
          if param_list is None:
              return []

          params = []
          for declaration in param_list.declarations:
              if not hasattr(declaration, "declarators"):
                  continue
              param_type = node_text(getattr(declaration, "type", None))
              for declarator in declaration.declarators:
                  if not hasattr(declarator, "name"):
                      continue
                  params.append(
                      {
                          "name": normalize_text(str(declarator.name)),
                          "raw_default": node_text(getattr(declarator, "initializer", None)),
                          "param_type": param_type
                      }
                  )
          return params

      def collect_syntax_ports(module_syntax):
          port_list = getattr(module_syntax.header, "ports", None)
          if port_list is None:
              return []

          ports = []
          for port in port_list.ports:
              if not (hasattr(port, "header") and hasattr(port, "declarator")):
                  continue
              ports.append(
                  {
                      "name": normalize_text(str(port.declarator.name)),
                      "direction": normalize_direction(str(port.header.direction)),
                      "raw_type": port_raw_type(port)
                  }
              )
          return ports

      def decompose_type(type_symbol):
          unpacked_dims = []
          current = type_symbol
          while getattr(current, "isUnpackedArray", False):
              unpacked_dims.append(int(current.range.width))
              current = current.elementType
          packed_widths = []
          while getattr(current, "isPackedArray", False):
              packed_widths.append(int(current.range.width))
              current = current.elementType
          if packed_widths:
              width = packed_widths.pop()
              packed_dims = packed_widths
          else:
              width = int(getattr(current, "bitWidth", 1) or 1)
              packed_dims = []
          return {
              "width": width,
              "signed": bool(getattr(type_symbol, "isSigned", False)),
              "packed_dims": packed_dims,
              "unpacked_dims": unpacked_dims
          }

      def fallback_raw_type(port_symbol):
          type_text = normalize_text(str(port_symbol.type))
          if not type_text:
              return None
          return type_text.replace("$", " ")

      def pick_raw_default(raw_default, value_text):
          if raw_default is None or raw_default == "":
              return value_text
          if "`" in raw_default:
              return value_text
          return raw_default

      def collect_semantic_signature(instance_body):
          params = []
          for param in instance_body.parameters:
              params.append(
                  {
                      "name": normalize_text(str(param.name)),
                      "value": normalize_text(str(param.value)),
                      "param_type": node_text(getattr(param, "type", None))
                  }
              )
          ports = []
          for port in instance_body.portList:
              port_data = decompose_type(port.type)
              port_data["name"] = normalize_text(str(port.name))
              port_data["direction"] = normalize_direction(str(port.direction))
              port_data["fallback_raw_type"] = fallback_raw_type(port)
              ports.append(port_data)
          return {"params": params, "ports": ports}

      def merge_signature(module_name, syntax_params, syntax_ports, semantic_signature):
          semantic_params = {}
          for param in semantic_signature["params"]:
              semantic_params[param["name"]] = param
          semantic_ports = {}
          for port in semantic_signature["ports"]:
              semantic_ports[port["name"]] = port

          params = []
          if syntax_params:
              for param in syntax_params:
                  semantic = semantic_params[param["name"]]
                  params.append(
                      {
                          "name": param["name"],
                          "value": semantic["value"],
                          "param_type": param["param_type"] or semantic["param_type"],
                          "raw_default": pick_raw_default(param["raw_default"], semantic["value"])
                      }
                  )
          else:
              for param in semantic_signature["params"]:
                  params.append(
                      {
                          "name": param["name"],
                          "value": param["value"],
                          "param_type": param["param_type"],
                          "raw_default": param["value"]
                      }
                  )

          ports = []
          if syntax_ports:
              for port in syntax_ports:
                  semantic = dict(semantic_ports[port["name"]])
                  semantic["name"] = port["name"]
                  semantic["direction"] = port["direction"]
                  semantic["raw_type"] = port["raw_type"] or semantic["fallback_raw_type"]
                  ports.append(semantic)
          else:
              for port in semantic_signature["ports"]:
                  port_data = dict(port)
                  port_data["raw_type"] = port["fallback_raw_type"]
                  ports.append(port_data)

          return {
              "module_name": module_name,
              "params": params,
              "ports": ports
          }

      def main():
          request = json.load(sys.stdin)
          files = [os.path.abspath(path) for path in request["files"]]
          top = request["top"]
          incdirs = [os.path.abspath(path) for path in request.get("incdirs", [])]
          defines = request.get("defines", {})
          param_overrides = request.get("param_overrides", {})

          source_manager = pyslang.SourceManager()
          add_user_directories(source_manager, incdirs + [os.path.dirname(path) for path in files])

          with tempfile.TemporaryDirectory() as temp_dir:
              wrapper_path = os.path.join(temp_dir, "__rsv_import_wrapper__.sv")
              with open(wrapper_path, "w", encoding="utf-8") as handle:
                  handle.write(wrapper_source(files, top, param_overrides, defines))

              tree = pyslang.SyntaxTree.fromFile(wrapper_path, source_manager)
              parse_errors = summarize_diagnostics(tree.diagnostics)
              if parse_errors:
                  raise RuntimeError("; ".join(parse_errors))

              compilation = pyslang.Compilation()
              compilation.addSyntaxTree(tree)
              semantic_errors = summarize_diagnostics(compilation.getAllDiagnostics())
              if semantic_errors:
                  raise RuntimeError("; ".join(semantic_errors))

              module_syntax = find_module_syntax(tree, top)
              instance_symbol = find_probe_instance(compilation)
              instance_body = instance_symbol.body

              return merge_signature(
                  top,
                  collect_syntax_parameters(module_syntax),
                  collect_syntax_ports(module_syntax),
                  collect_semantic_signature(instance_body)
              )

      if __name__ == "__main__":
          try:
              json.dump(main(), sys.stdout)
          except Exception as exc:
              json.dump({"error": str(exc)}, sys.stdout)
              sys.exit(1)
    PY

    attr_reader :name

    def initialize(name:, files:, incdirs:, defines:)
      @name = name
      @files = files
      @incdirs = incdirs
      @defines = normalize_define_map(defines)
      @definition_cache = {}
      @definition_handle_cache = {}
    end

    def new(*args, **kwargs)
      raise ArgumentError, "imported SystemVerilog modules do not accept positional arguments" unless args.empty?

      current_module = RSV.current_module_def
      return current_module.send(:instantiate_module, self, **kwargs) if current_module

      build_definition(**kwargs)
    end

    def definition(*args, **kwargs)
      raise ArgumentError, "imported SystemVerilog modules do not accept positional arguments" unless args.empty?

      overrides = normalize_override_map(kwargs)
      cache_key = JSON.dump(overrides.sort.to_h)
      @definition_handle_cache[cache_key] ||= ModuleDefinitionHandle.new(build_definition(**kwargs))
    end

    def build_definition(*args, **kwargs)
      raise ArgumentError, "imported SystemVerilog modules do not accept positional arguments" unless args.empty?

      overrides = normalize_override_map(kwargs)
      cache_key = JSON.dump(overrides.sort.to_h)
      @definition_cache[cache_key] ||= extract_definition(overrides)
    end

    private

    def extract_definition(overrides)
      signature = run_helper(overrides)
      params = signature.fetch("params").map do |param|
        ParamDecl.new(
          param.fetch("name"),
          param.fetch("value"),
          param["param_type"],
          raw_default: param["raw_default"]
        )
      end
      ports = signature.fetch("ports").map do |port|
        w = port.fetch("width")
        port.fetch("packed_dims").each { |d| w *= d }
        signal = SignalSpec.new(
          port.fetch("name"),
          width: w,
          signed: port.fetch("signed"),
          unpacked_dims: port.fetch("unpacked_dims")
        )
        PortDecl.new(port.fetch("direction").to_sym, signal, raw_type: port["raw_type"])
      end
      ImportedModuleDefinition.new(signature.fetch("module_name"), params, ports)
    end

    def run_helper(overrides)
      request = {
        top: @name,
        files: @files,
        incdirs: @incdirs,
        defines: @defines,
        param_overrides: overrides
      }
      stdout, stderr, status = Open3.capture3("python3", "-c", PYSLANG_HELPER, stdin_data: JSON.dump(request))
      result = JSON.parse(stdout)
      detail = result["error"] || stderr.strip
      raise RuntimeError, "failed to import #{@name}: #{detail}" if !status.success? || result["error"]

      result
    rescue Errno::ENOENT
      raise RuntimeError, "python3 is required for RSV.import_sv"
    rescue JSON::ParserError
      detail = stderr.strip
      detail = stdout.strip if detail.empty?
      raise RuntimeError, "failed to import #{@name}: #{detail}"
    end

    def normalize_define_map(defines)
      defines.each_with_object({}) do |(name, value), memo|
        memo[name.to_s] = value == true || value.nil? ? nil : value.to_s
      end
    end

    def normalize_override_map(overrides)
      overrides.each_with_object({}) do |(name, value), memo|
        unless value.is_a?(String) || value.is_a?(Numeric)
          raise TypeError, "parameter override #{name} must be a String or Numeric"
        end

        memo[name.to_s] = value.to_s
      end
    end
  end

  def self.import_sv(path = nil, top:, files: nil, incdirs: [], defines: {})
    file_list = Array(files)
    file_list.unshift(path) if path
    file_list = file_list.flatten.compact.map { |file| File.expand_path(file) }.uniq
    raise ArgumentError, "import_sv expects at least one SystemVerilog source file" if file_list.empty?

    ImportedModule.new(
      name: top.to_s,
      files: file_list,
      incdirs: Array(incdirs).map { |dir| File.expand_path(dir) }.uniq,
      defines: defines
    )
  end
end
