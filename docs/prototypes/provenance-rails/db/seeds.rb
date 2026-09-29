sample = JSON.parse(Rails.root.join("test/fixtures/files/romans_pages.json").read)
import = OcrImport.new(title: sample["title"], pages: sample["pages"])
import.save || abort(import.errors.full_messages.to_sentence)
puts "Imported #{import.document.title}: #{Rails.application.routes.url_helpers.document_path(import.document)}"
