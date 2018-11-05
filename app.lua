------------------------------------------------------------------------------
-- Safe maths
------------------------------------------------------------------------------
local M = {}

function M.add(a, b)
    if a == nil then a = 0 end
    if b == nil then b = 0 end

    local c = a + b
    assert(c >= a, "number overflow")

    return c
end

function M.sub(a, b)
    if a == nil then a = 0 end
    if b == nil then b = 0 end

    assert(b <= a, "first value must be bigger than second one")
    local c = a - b

    return c
end

function M.mul(a, b)
    if a == nil then a = 0 end
    if b == nil then b = 0 end

    local c = a * b
    assert(a == 0 or c/a == b, "number overflow")

    return c
end

function M.div(a, b)
    if a == nil then a = 0 end
    if b == nil then b = 0 end

    assert(b > 0, "second value must be bigger than 0")
    c = a / b

    return c
end


Mixer = {}
MixerMetatable = { __index = Mixer }
setmetatable(Mixer, {
    __call = function(cls, ...)
        return cls.new(...)
    end
})

function Mixer.new(...)
    local r = {}
    for k, v in ipairs{...} do
        r = v.new(r)
    end
    return r
end


Sequence = {}
SequenceMetatable = { __index = Sequence }
setmetatable(Sequence, {
    __call = function(cls, ...)
        return cls.new(...)
    end
})

function Sequence.new(name)
    return setmetatable({name = 'sequence-' .. name}, SequenceMetatable)
end

function Sequence:next()
    local currentSequence = system.getItem(self.name)
    if (nil == currentSequence) then
        currentSequence = 0
    end
    local nextSequence = currentSequence + 1
    system.setItem(self.name, nextSequence)
    return nextSequence;
end

--- mint.lua
MintService = { }
MintServiceMetatable = { __index = MintService }
setmetatable(MintService, {
    __call = function(cls, ...)
        return cls.new(...)
    end
})

function MintService.new(parent)
    return setmetatable({ parent = parent },
        MintServiceMetatable)
end

function MintService:totalAmount(assetSymbol)
    if AssetTypes.exists(assetSymbol) then
        local mintInfo = system.getItem('mint-' .. assetSymbol)
        return mintInfo.amount or -1
    else
        return -1
    end
end

function MintService:issue(assetSymbol, amount)
    amount = tonumber(amount)
    assert(0 < amount)
    if not AssetTypes.exists(assetSymbol) then
        AssetTypes.register(assetSymbol)
    end
    local issuer = system.getSender()
    local mintInfo = system.getItem('mint-' .. assetSymbol) or { issuer = issuer, amount = 0 }
    assert(mintInfo.issuer == issuer, 'no authority')

    mintInfo.amount = M.add(mintInfo.amount, amount)
    system.setItem('mint-' .. assetSymbol, mintInfo)

    if self.parent and self.parent.balanceService then
        self.parent.balanceService:receiveFromExternal(issuer, assetSymbol, amount)
    end

end

MintServiceComponent = {}
MintServiceComponentMetatable = { __index = MintServiceComponent }
setmetatable(MintServiceComponent, {
    __call = function(cls, ...)
        return cls.new(...)
    end
})

function MintServiceComponent.new(o)
    local data = o or {}
    data.mintService = MintService(data)
    return setmetatable(data, MintServiceMetatable)
end

--- balance.lua

BalanceService = { }
BalanceServiceMetatable = { __index = BalanceService }
setmetatable(BalanceService, {
    __call = function(cls, ...)
        return cls.new(...)
    end
})

function BalanceService.new(parent)
    return setmetatable({ parent = parent }, BalanceServiceMetatable)
end

function BalanceService:getAmount(address, assetSymbol)
    assert(nil ~= address)
    local account = system.getItem('account-' .. address)
    if nil == account then
        return 0
    else
        return account[assetSymbol] or 0
    end
end

function BalanceService:receiveFromExternal(receiverAddress, assetSymbol, amount)
    amount = tonumber(amount)
    local receiverAccount = system.getItem('account-' .. receiverAddress) or { balance = 0 }
    assert(0 < amount)
    assert(nil ~= receiverAddress)
    local key = assetSymbol
    receiverAccount[key] = M.add(receiverAccount[key] or 0, amount)

    system.setItem('account-' .. receiverAddress, receiverAccount)

    if nil ~= self.parent and nil ~= self.parent.historyService then
        local tx = Transaction(2, nil, receiverAddress, assetSymbol, amount)
        self.parent.historyService:record(tx)
    end
end

function BalanceService:transfer(receiverAddress, assetSymbol, amount)
    amount = tonumber(amount)
    local senderAddress = system.getSender()
    local senderAccount = system.getItem('account-' .. senderAddress)
    local receiverAccount = system.getItem('account-' .. receiverAddress) or { balance = 0 }

    assert(0 < amount)
    assert(nil ~= receiverAddress)
    assert(nil ~= senderAccount)
    local key = assetSymbol
    assert(amount <= senderAccount[key], 'insufficient balance')
    senderAccount[key] = M.sub(senderAccount[key] or 0, amount)
    receiverAccount[key] = M.add(receiverAccount[key] or 0, amount)

    system.setItem('account-' .. senderAddress, senderAccount)
    system.setItem('account-' .. receiverAddress, receiverAccount)

    if nil ~= self.parent and nil ~= self.parent.historyService then
        local tx = Transaction(1, senderAddress, receiverAddress, assetSymbol, amount)
        self.parent.historyService:record(tx)
    end
end


BalanceServiceComponent = {}
BalanceServiceComponentMetatable = { __index = BalanceServiceMetatable }
setmetatable(BalanceServiceComponent, {
    __call = function(cls, ...)
        return cls.new(...)
    end
})

function BalanceServiceComponent.new(o)
    local data = o or {}
    data.balanceService = BalanceService(data)
    return setmetatable(data, BalanceServiceComponentMetatable)
end


Transaction = { }
TransactionMetatable = { __index = Transaction }
setmetatable(Transaction, {
    __call = function(cls, ...)
        return cls.new(...)
    end
})

function Transaction.new(type, sender, receiver, assetType, amount)
    setmetatable({
        type = type,
        sender = sender,
        receiver = receiver,
        assetType = assetType,
        amount = amount
    }, TransactionMetatable)
end


HistoryService = {}
HistoryServiceMetatable = { __index = HistoryService }
setmetatable(HistoryService, {
    __call = function(cls, ...)
        return cls.new(...)
    end
})
function HistoryService.new(parent)
    return setmetatable(
        { parent = parent, sequence = Sequence('history') },
        HistoryServiceMetatable)
end

function HistoryService:record(transaction)
    system.setItem('history-' .. self.sequence:next(), transaction)
end

HistoryServiceComponent = {}
HistoryServiceComponentMetatable = { __index = HistoryServiceComponent }
setmetatable(HistoryServiceComponent, {
    __call = function(cls, ...)
        return cls.new(...)
    end
})

function HistoryServiceComponent.new(o)
    local data = o or {}
    data.historyService = HistoryService(data)
    return setmetatable(data, HistoryServiceComponentMetatable)
end
--- asset.lua
AssetType = { }
AssetTypeMetatable = { __index = AssetType }
setmetatable(AssetType, {
    __call = function(cls, ...)
        return cls.new(...)
    end
})

AssetTypes = {}

function AssetTypes.exists(symbol)
  return nil ~= system.getItem('symbol-' .. symbol)
end

function AssetTypes.register(symbol)
    assert(not AssetTypes.exists(symbol))
    system.setItem('symbol-' .. symbol, symbol)
end




local tokenSystem = Mixer(MintServiceComponent, BalanceServiceComponent, HistoryServiceComponent)

function constructor()
	tokenSystem.mintService:issue('aergo-token', 300000000)
end

function transfer(receiver, amount)
	tokenSystem.balanceService:transfer(receiver, 'aergo-token', amount)
end

function getAmount(address)
	return tokenSystem.balanceService:getAmount(address, 'aergo-token')
end

abi.register(transfer, getAmount)
