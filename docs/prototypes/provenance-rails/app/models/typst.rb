# The Typst CLI (https://typst.app). Set TYPST to its path if it isn't on PATH.
module Typst
  class CompilationError < StandardError; end

  extend self

  def compile(source, standard: "a-2b")
    Dir.mktmpdir do |dir|
      input, output = File.join(dir, "document.typ"), File.join(dir, "document.pdf")
      File.write(input, source)

      _stdout, stderr, status = Open3.capture3(binary, "compile", "--pdf-standard", standard, input, output)
      raise CompilationError, stderr unless status.success?

      File.binread(output)
    end
  end

  def available?
    system(binary, "--version", out: File::NULL, err: File::NULL)
  end

  private
    def binary
      ENV.fetch("TYPST", "typst")
    end
end
