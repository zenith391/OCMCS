local perlin = api_require("noise")

return {
	height = function(x, z)
		local noise = (perlin:noise(x/16, z/16) + 1) / 2
		return math.floor(noise*16)
	end,
	block = function(x, y, z)
		local noise = (perlin:noise(x/16, z/16) + 1) / 2
		local height = math.floor(noise*16)
		if y == height then
			return 9 -- grass block
		elseif y == 0 then
			return 33 -- bedrock
		elseif y < height then
			return 10 -- dirt
		else
			return 0 -- air
		end
	end
} 
