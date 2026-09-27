; 2.6.4: 'AB' alone is two bytes; 'AB' in an expression is one
a:  db  'AB'
b:  db  'AB' AND 0ffh
c:  db  'X',1,'YZ'
d:  db  ',',1
e:  ret
