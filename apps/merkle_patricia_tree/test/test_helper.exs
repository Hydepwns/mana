ExUnit.configure(timeout: :infinity)
ExUnit.start()

# Load support files
{:ok, files} = File.ls("./test/support")

Enum.each(files, fn file ->
  Code.require_file("support/#{file}", __DIR__)
end)

# Setup test mocks for faster testing
MerklePatriciaTree.Test.Helper.setup_mocks()
