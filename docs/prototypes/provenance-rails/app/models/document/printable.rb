# Print-ready PDFs through Typst, which embeds fonts and can enforce PDF/A.
# Print-on-demand vendors usually want PDF/X, which Typst doesn't produce, so
# budget for a conversion step (or another typesetter) once the vendor's spec
# is known.
module Document::Printable
  def to_typst
    ApplicationController.render(template: "documents/print", formats: [ :typ ], layout: false,
      assigns: { document: self, body: Document::TypstSource.new(content).to_s })
  end

  def to_pdf(standard: "a-2b")
    Typst.compile(to_typst, standard:)
  end
end
