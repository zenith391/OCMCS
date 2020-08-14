return {
	height = function(x, z)
		return 3
	end,
	block = function(x, y, z)
		if y == 3 then
			return 9
		elseif y == 2 or y == 1 then
			return 10 -- dirt
		elseif y == 0 then
			return 33 -- bedrock
		else
			return 0 -- air
		end
	end
}
