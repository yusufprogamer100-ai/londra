local ok, Londra = pcall(require, './dist/londra')
print('Require ok:', ok)
if ok and type(Londra) == 'table' then
	print('Londonra type: table')
	for k, v in pairs(Londra) do
		print('  ', k, type(v))
	end
else
	print('Londonra type:', type(Londra))
	print('Londonra:', tostring(Londra))
end
print('Londra.__inject:', Londres.__inject)