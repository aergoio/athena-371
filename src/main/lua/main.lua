import "aergoio/athena-370"

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

