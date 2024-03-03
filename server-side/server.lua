local Tunnel = module("vrp","lib/Tunnel")
local Proxy = module("vrp","lib/Proxy")
local htmlEntities = module("vrp", "lib/htmlEntities")
local sanitizes = module("vrp", "cfg/sanitizes")

vRP = Proxy.getInterface("vRP")
vRPclient = Tunnel.getInterface("vRP")
vMenu = Tunnel.getInterface("passos_business")

Passos = {}
Proxy.addInterface("passos_business", Passos)
Tunnel.bindInterface("passos_business", Passos)

vRP.prepare("vRP/create_business","INSERT IGNORE INTO vrp_user_business(user_id,name,description,capital,laundered,reset_timestamp,taxa_de_crescimento) VALUES(@user_id,@name,'',@capital,0,@time,0)")
vRP.prepare("vRP/delete_business", "DELETE FROM vrp_user_business WHERE user_id = @user_id")
vRP.prepare("vRP/get_business", "SELECT * FROM vrp_user_business WHERE user_id = @user_id")
vRP.prepare("vRP/get_users", "SELECT * FROM vrp_user_business")
vRP.prepare("vRP/add_capital", "UPDATE vrp_user_business SET capital = capital + @capital WHERE user_id = @user_id")
vRP.prepare("vRP/rem_capital", "UPDATE vrp_user_business SET capital = capital - @capital WHERE user_id = @user_id")
vRP.prepare("vRP/set_capital", "UPDATE vrp_user_business SET capital = @capital WHERE user_id = @user_id")
vRP.prepare("vRP/add_laundered", "UPDATE vrp_user_business SET laundered = laundered + @laundered WHERE user_id = @user_id")
vRP.prepare("vRP/get_business_page", "SELECT user_id,name,description,capital,capital_trancada,taxa_de_crescimento FROM vrp_user_business ORDER BY capital DESC LIMIT @b,@n")
vRP.prepare("vRP/reset_transfer", "UPDATE vrp_user_business SET laundered = 0, reset_timestamp = @time WHERE user_id = @user_id")
vRP.prepare("vRP/update_capital_trancada", "UPDATE vrp_user_business SET capital_trancada = @capital_trancada WHERE user_id = @user_id")
vRP.prepare("vRP/upgrade_taxa", "UPDATE vrp_user_business SET taxa_de_crescimento = taxa_de_crescimento + 1 WHERE user_id = @user_id")

local CooldownSaque = {}
-----------------------------------------------------------------------------------------------------------------------------------------
-- Funções
-----------------------------------------------------------------------------------------------------------------------------------------
function Notify(a, b, c)
	TriggerClientEvent("Notify", a, b, c)
end

function getTaxaMultiplier(nivel)
	return cfg.Multiplicador[nivel]
end

function getPorcentagemLavagem(nivel)
	return cfg.PorcentagemLavagem[nivel]
end

function getPrecoNivel(nivel)
	return cfg.Precos[nivel]
end

local function businessList(player, page)
	local user_id = vRP.getUserId(player)
	if page < 0 then page = 0 end
	local businessList = vRP.buildMenu("businessList", { player = player })
	businessList.name = "Câmara de Negócios"
	local rows = vRP.query("vRP/get_business_page", {b = page*10, n = 10})
	if rows[1] then
		local count = 0
		for k,v in pairs(rows) do
			count = count+1
			local row = v
		
			if row.user_id ~= nil then
				local nplayer = vRP.getUserSource(row.user_id)
				local identity = vRP.getUserIdentity(row.user_id)

				if identity then
					businessList[htmlEntities.encode(row.name)] = {function(player, choice)
						if vRP.hasPermission(user_id, cfg.BusinessManagePermission) then
							local businessManager = vRP.buildMenu("businessManager", { player = player })
							businessManager.name = "Gerenciar Negócios"

							print(json.encode(row))
							if row.capital_trancada == 0 then
								businessManager["Trancar Capital"] = {function(player, choice)
									vRP.execute("vRP/update_capital_trancada", { user_id = row.user_id, capital_trancada = 1 })
									Notify(player, "importante", "Você trancou a capital da empresa de <b>".. identity.name .." ".. identity.firstname .."</b>.")

									if nplayer then
										Notify(nplayer, "importante", "O seu capital foi trancado pela <b>Polícia Civil</b>. Sua empresa está passando por investigações.")
									end
								end}
							elseif row.capital_trancada == 1 then
								businessManager["Liberar Capital"] = {function(player, choice)
									vRP.execute("vRP/update_capital_trancada", { user_id = row.user_id, capital_trancada = 0 })
									Notify(player, "sucesso", "Você liberou a capital da empresa de <b>".. identity.name .." ".. identity.firstname .."</b>.")

									if nplayer then
										Notify(nplayer, "aviso", "O seu capital foi liberado pela <b>Polícia Civil</b>.")
									end
								end}
							end

							businessManager["Fechar Empresa"] = {function(player, choice)
								vRP.execute("vRP/delete_business", { user_id = row.user_id })
								Notify(player, "importante", "Você fechou a empresa de <b>".. identity.name .." ".. identity.firstname .."</b>.")

								if nplayer then
									Notify(nplayer, "importante", "A sua empresa foi fechada pela <b>Polícia Civil</b>.")
								end
							end}
							vRP.openMenu(player, businessManager)
						else
							Notify(player, "negado", "Somente um delegado tem poder para gerenciar empresas de terceiros.")
							vRP.closeMenu(player, businessList)
						end
					end, "Capital: </em>R$ ".. vRP.format(tonumber(row.capital)) ..",00 <br /><em>Nível de Taxa de Crescimento: </em>".. row.taxa_de_crescimento .." (".. getTaxaMultiplier(tonumber(row.taxa_de_crescimento)) .." %)<br /><em>Proprietário: </em>".. identity.name .." ".. identity.firstname .."<br /><em>RG: </em>".. identity.registration .."<br /><em>Telefone: </em>".. identity.phone}
				end
		
				count = count-1
				if count == 0 then
					businessList["> Avançar"] = {function() businessList(player,page+1) end}
					businessList["> Voltar"] = {function() businessList(player,page-1) end}
			
					vRP.openMenu(player, businessList)
				end
			end
		end
	else
		businessList["Não há nenhuma empresa aberta"] = {function(player, choice)
			vRP.closeMenu(player, businessList)
		end}
	end
	vRP.openMenu(player,businessList)
end

function Passos.getUserBusiness(user_id)
	if user_id then
		local rows = vRP.query("vRP/get_business", { user_id = user_id })
		local business = rows[1]

		if business and os.time() >= business.reset_timestamp+cfg.Intervalo*60 then
			vRP.execute("vRP/reset_transfer", {user_id = user_id, time = os.time() })
			business.laundered = 0
		end

		return business
	end
	return 
end

function Passos.closeBusiness(user_id)
  	vRP.execute("vRP/delete_business", { user_id = user_id })
end

function Passos.openBusiness()
	local source = source
	local user_id = vRP.getUserId(source)
	if user_id then
		local business = vRP.buildMenu("business", { player = source })

		local user_business = Passos.getUserBusiness(user_id)
		if user_business == nil then
			business.name = cfg.ServerName .."'s Business"
			business["Abrir uma Empresa"] = {function(player, choice)
				local capital_inicial = vRP.prompt(player, "Qual é o capital inicial que você quer aplicar na sua empresa? (Mínimo: ".. vRP.format(tonumber(cfg.CapitalMinimo))..",00 reais)", cfg.CapitalMinimo)
				if capital_inicial == "" or capital_inicial == nil then
					Notify(player, "negado", "A quantidade inserida é inválida.")
					return 
				end
				if tonumber(capital_inicial) > 0 then
					if tonumber(capital_inicial) >= tonumber(cfg.CapitalMinimo) then
						local nome_empresa = vRP.prompt(player, "Qual é o nome que você deseja colocar na sua empresa? (Isso é imutável).", "")
						if nome_empresa ~= nil or nome_empresa ~= "" then
							if vRP.tryFullPayment(user_id, tonumber(capital_inicial)) then
								vRP.execute("vRP/create_business", { user_id = user_id, name = nome_empresa, capital = tonumber(capital_inicial), time = os.time() })
								Notify(player, "sucesso", "Você abriu uma empresa!")
							else
								Notify(player, "negado", "Você não tem essa quantia para aplicar na sua empresa.")
							end
						else
							Notify(player, "negado", "O nome inserido é inválido.")
						end
					else
						Notify(player, "negado", "O valor inicial inserido é inválido. O capital inicial mínimo é: <b>".. vRP.format(tonumber(cfg.CapitalMinimo)) ..",00 reais</b>.")
					end
				else
					Notify(player, "negado", "A quantidade inserida é inválida.")
				end
				
			end, "Abra uma empresa e crie o seu negócio."}
		else
			business.name = user_business.name 
			business["> Sobre a minha empresa."] = {function(player, choice)
			end, "Nome: </em>".. user_business.name .."<br /><em>Capital: </em>R$ ".. vRP.format(tonumber(user_business.capital)) ..",00 <br /><em>Nível de Taxa de Crescimento: </em>".. user_business.taxa_de_crescimento .." (".. getTaxaMultiplier(tonumber(user_business.taxa_de_crescimento)) .." %)"}
			
			business["Adicionar Capital"] = {function(player, choice)
				if user_business.capital_trancada == 0 then
					local valor = vRP.prompt(player, "Quantos reais você quer adicionar?", "")
					if valor == "" or valor == nil then
						Notify(player, "negado", "A quantidade inserida é inválida.")
						return 
					end
					if tonumber(valor) > 0 then
						if vRP.tryPayment(user_id, tonumber(valor)) then
							vRP.execute("vRP/add_capital", { user_id = user_id, capital = tonumber(valor) })
							Notify(player, "sucesso", "Você aplicou <b>R$ ".. vRP.format(tonumber(valor)) ..",00</b> na sua empresa!")
						else
							Notify(player, "negado", "Você não tem essa quantia para aplicar na sua empresa.")
						end
					else
						Notify(player, "negado", "A quantidade inserida é inválida.")
					end
				else
					Notify(player, "negado", "O seu capital foi trancado pela <b>Polícia Civil</b>. Sua empresa está passando por investigações.")
				end
			end, "Adicione mais capital à sua empresa e deixe ela cada vez mais rica e poderosa."}
			business["Aumentar Taxa de Crescimento"] = {function(player, choice)
				if user_business.capital_trancada == 0 then
					local taxaCrescimento = vRP.buildMenu("taxaCrescimento", { player = player })
					taxaCrescimento.name = "Taxa de Crescimento"
					
					taxaCrescimento["> O que é Taxa de Crescimento?"] = {function() end, "A taxa de crescimento é o reflexo da capacidade de expansão da sua empresa e do aumento do capital. Ao aumentar essa taxa, você gradualmente acumulará um capital cada vez maior, possibilitando o fortalecimento e a prosperidade do seu empreendimento."}
					
					if user_business.taxa_de_crescimento == 0 then
						taxaCrescimento["Aumentar Para o Nível 1 - R$ ".. vRP.format(tonumber(getPrecoNivel(1))) ..",00."] = {function(player, choices)
							if vRP.tryFullPayment(user_id, tonumber(getPrecoNivel(1))) then
								vRP.execute("vRP/upgrade_taxa", { user_id = user_id })
								vRP.closeMenu(player, taxaCrescimento)
								Notify(player, "sucesso", "Você aumentou a capacidade de crescimento da sua empresa!")
							else
								Notify(player, "negado", "Dinheiro Insuficiente.")
							end
						end, "Ao elevar para o nível um, você alcançará uma taxa de acumulação de capital de 45% e receberá 65% do valor em lavagens de dinheiro."}
					elseif user_business.taxa_de_crescimento == 1 then
						taxaCrescimento["Aumentar Para o Nível 2 - R$ ".. vRP.format(tonumber(getPrecoNivel(2))) ..",00."] = {function(player, choices)
							if vRP.tryFullPayment(user_id, tonumber(getPrecoNivel(2))) then
								vRP.execute("vRP/upgrade_taxa", { user_id = user_id })
								vRP.closeMenu(player, taxaCrescimento)
								Notify(player, "sucesso", "Você aumentou a capacidade de crescimento da sua empresa!")
							else
								Notify(player, "negado", "Dinheiro Insuficiente.")
							end
						end, "Ao elevar para o nível um, você alcançará uma taxa de acumulação de capital de 55% e receberá 75% do valor em lavagens de dinheiro."}
					elseif user_business.taxa_de_crescimento == 2 then
						taxaCrescimento["Aumentar Para o Nível 3 - R$ ".. vRP.format(tonumber(getPrecoNivel(3))) ..",00."] = {function(player, choices)
							if vRP.tryFullPayment(user_id, tonumber(getPrecoNivel(3))) then
								vRP.execute("vRP/upgrade_taxa", { user_id = user_id })
								vRP.closeMenu(player, taxaCrescimento)
								Notify(player, "sucesso", "Você aumentou a capacidade de crescimento da sua empresa!")
							else
								Notify(player, "negado", "Dinheiro Insuficiente.")
							end
						end, "Ao elevar para o nível um, você alcançará uma taxa de acumulação de capital de 75% e receberá 89% do valor em lavagens de dinheiro."}
					elseif user_business.taxa_de_crescimento == 3 then
						taxaCrescimento["Aumentar Para o Nível 4 - R$ ".. vRP.format(tonumber(getPrecoNivel(4))) ..",00."] = {function(player, choices)
							if vRP.tryFullPayment(user_id, tonumber(getPrecoNivel(4))) then
								vRP.execute("vRP/upgrade_taxa", { user_id = user_id })
								Notify(player, "sucesso", "Você aumentou a capacidade de crescimento da sua empresa!")
								vRP.closeMenu(player, taxaCrescimento)
							else
								Notify(player, "negado", "Dinheiro Insuficiente.")
							end
						end, "Ao elevar para o nível um, você alcançará uma taxa de acumulação de capital de 90% e receberá 100% do valor em lavagens de dinheiro."}
					elseif user_business.taxa_de_crescimento == 4 then
						taxaCrescimento["Nível máximo alcançado."] = {function(player, choices)
						end, "A sua empresa chegou ao nível máximo de crescimento. Não há mais nada aqui."}
					end

					vRP.openMenu(player, taxaCrescimento)
				else
					Notify(player, "negado", "O seu capital foi trancado pela <b>Polícia Civil</b>. Sua empresa está passando por investigações.")
				end
			end, "Aumente a capacidade de crescimento da sua empresa. Isso fará seu capital crescer."}
			business["Lavar Dinheiro"] = {function(player, choice)
				if user_business.capital_trancada == 0 then
					local valor = vRP.prompt(player, "Quantos reais você quer lavar?", "")
					if valor == "" or valor == nil then
						Notify(player, "negado", "A quantidade inserida é inválida.")
						return 
					end
					if tonumber(valor) > 0 then
						local dinheiroSujo = vRP.getInventoryItemAmount(user_id, "dinheirosujo")
						if tonumber(dinheiroSujo) >= tonumber(valor) then
							vRP.tryGetInventoryItem(user_id, "dinheirosujo", tonumber(valor))

							local porcentagem_recebida = "50%"
							local porcentagem_a_receber = tonumber(cfg.PorcentagemLavagem[user_business.taxa_de_crescimento])
							
							if porcentagem_a_receber == 0.65 then
								porcentagem_recebida = "65%"
							elseif porcentagem_a_receber == 0.75 then
								porcentagem_recebida = "75%" 
							elseif porcentagem_a_receber == 0.89 then
								porcentagem_recebida = "89%"
							elseif porcentagem_a_receber == 1 then
								porcentagem_recebida = "100%"
							end

							vRP.execute("vRP/add_laundered", { laundered = tonumber(valor) })
							vRP.giveMoney(user_id, tonumber(valor)*porcentagem_a_receber)

							if porcentagem_a_receber < 1 then
								Notify(player, "aviso", "Você lavou <b>R$ ".. vRP.format(tonumber(valor)) ..",00</b> e recebeu <b>".. porcentagem_recebida .."</b>.\nAumente a <b>taxa de crescimento</b> da sua empresa para obter maiores retornos em lavagens.")
							else
								Notify(player, "sucesso", "Você lavou <b>R$ ".. vRP.format(tonumber(valor)) ..",00</b> e recebeu <b>".. porcentagem_recebida .."</b>.")
							end
						else
							Notify(player, "negado", "Você não tem essa quantidade de <b>dinheiro sujo</b>.")
						end
					else
						Notify(player, "negado", "A quantidade inserida é inválida.")
					end
				else
					Notify(player, "negado", "O seu capital foi trancado pela <b>Polícia Civil</b>. Sua empresa está passando por investigações.")
				end
			end, "Lave dinheiro com a sua empresa e lucre muito mais."}
			business["Sacar Capital"] = {function(player, choice)
				if user_business.capital_trancada == 0 then
					local valor = vRP.prompt(player, "Quantos reais você quer sacar do seu capital?", "")
					if valor == "" or valor == nil then
						Notify(player, "negado", "A quantidade inserida é inválida.")
						return 
					end
					if tonumber(valor) > 0 then
						if tonumber(user_business.capital) >= tonumber(valor) then
							if tonumber(CooldownSaque[user_id]) > 0 then
								Notify(player, "negado", "Você precisa esperar <b>".. CooldownSaque[user_id] .." minutos</b> para sacar novamente.")
								return
							end

							if tonumber(valor) > 500000 then
								Notify(player, "negado", "Você só pode sacar até 500.000 reais.")
								return
							end

							vRP.giveBankMoney(user_id, tonumber(valor))
							vRP.execute("vRP/rem_capital", { user_id = user_id, capital = tonumber(valor) })
							Notify(player, "sucesso", "Você sacou <b>R$ ".. vRP.format(tonumber(valor)) ..",00</b>.")
							CooldownSaque[user_id] = 30
							
							Wait(1200)

							if (tonumber(user_business.capital) - tonumber(valor)) < cfg.CapitalMinimo then
								vRP.execute("vRP/update_capital_trancada", { user_id = user_id, capital_trancada = 1 })
								Notify(player, "negado", "O saldo do seu capital ficou menor que o mínimo estabelecido pela <b>Receita Federal</b>. Agora, você precisará pedir para que a polícia destranque a sua empresa.")
							end
						else
							Notify(player, "negado", "Você não tem essa quantidade de <b>capital aplicado</b>.")
						end
					else
						Notify(player, "negado", "A quantidade inserida é inválida.")
					end
				else
					Notify(player, "negado", "O seu capital foi trancado pela <b>Polícia Civil</b>. Sua empresa está passando por investigações.")
				end
			end, "Saque um valor do seu capital. Mas, fique atento, você só tem permissão de sacar até 500.000 reais, a cada 30 minutos, e se o capital ficar menor que o mínimo estabelecido, a sua empresa será trancada e só será liberada com autorização policial."}
		end

		if vRP.hasPermission(user_id, cfg.PolicePermission) then
			business["> Câmara de Negócios"] = {function(player, choice)
				businessList(player, 0)
			end, "Bem-vindo a Life Invader. Por ser membro da corporação de Polícia Civil, você tem acesso a Câmara de Negócios."}
		end
		vRP.openMenu(source, business)

	end
end

function Passos.updateCapital()
	local rows = vRP.query("vRP/get_users", {})
	if #rows > 0 then
		for k,v in pairs(rows) do 
			local user_id = v.user_id
			local source = vRP.getUserSource(v.user_id)

			local user_business = Passos.getUserBusiness(user_id)
			if user_business ~= nil then
				local capital_old = tonumber(user_business.capital)
				local capital_new = capital_old * (1 + getTaxaMultiplier(tonumber(user_business.taxa_de_crescimento)))
				vRP.execute("vRP/set_capital", { user_id = user_id, capital = capital_new })
				if source then
					Notify(source, "sucesso", "O capital da sua empresa aumentou! O seu capital era <b>R$".. vRP.format(capital_old) ..",00</b>, agora, tem o valor de <b>R$".. vRP.format(capital_new) ..",00</b>.")
				end
			end
		end
	end
end

Citizen.CreateThread(function()
	while true do
		Passos.updateCapital()
		Citizen.Wait(cfg.CapitalUpdate)
	end
end)

Citizen.CreateThread(function()
	while true do
		for k,v in pairs(CooldownSaque) do
			if CooldownSaque[k] > 0 then
				CooldownSaque[k] = CooldownSaque[k] - 1
			end
		end
		Citizen.Wait(30*60000)
	end
end)
