local Londra = require('./dist/londra')
print('Londra.__inject type:', type(Londra.__inject))
print('Londra.__inject nil:', Londra.__inject == nil)
if Londra.__inject then
	print('Londra.__inject works')
	Londra.__inject('test')
end