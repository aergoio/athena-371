import 'aergoio/athena-343'

local suite = TestSuite('test-all')

suite:add(TestCase('#transfer', function()
  system.getSender = function()
    return "executor"
  end
  constructor()
  transfer('receiver', 1000)
  assertEquals(1000, getAmount('receiver'))
  assertEquals(299999000, getAmount('executor'))
end))

suite:run()