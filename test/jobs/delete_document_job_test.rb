require "test_helper"

class DeleteDocumentJobTest < ActiveJob::TestCase
  include ActiveJob::TestHelper

  test "deletes a very large document in bounded batches and reports remaining progress" do
    document = create_document("large", passage_count: 2_501)
    updates = []
    original = document.method(:update_columns)
    document.define_singleton_method(:update_columns) do |attributes|
      updates << attributes[:deletion_remaining] if attributes.key?(:deletion_remaining)
      original.call(attributes)
    end

    DeleteDocumentJob.perform_now(document)

    assert_equal [ 1_501, 501, 0 ], updates
    assert_not Document.exists?(document.id)
    assert_equal 0, Passage.where(document_id: document.id).count
  end

  test "deletes a document with no passages" do
    document = create_document("empty", passage_count: 0)

    DeleteDocumentJob.perform_now(document)

    assert_not Document.exists?(document.id)
  end

  test "marks a failed deletion and preserves an error for retry" do
    document = create_document("failure", passage_count: 1)
    document.define_singleton_method(:destroy!) { raise "disk removal failed" }
    DeleteDocumentJob.perform_now(document)

    assert_equal "deletion_failed", document.reload.status
    assert_match "disk removal failed", document.error_message
  end

  private

  def create_document(name, passage_count:)
    document = Document.create!(title: name.titleize, original_filename: "#{name}.txt", content_type: "text/plain",
      stored_path: "storage/archive_files/#{name}.txt", status: "ready", passage_count: passage_count)
    now = Time.current
    (0...passage_count).each_slice(500) do |positions|
      document.passages.insert_all!(positions.map do |position|
        { position:, body: "Passage #{position}", created_at: now, updated_at: now }
      end)
    end
    document
  end
end
