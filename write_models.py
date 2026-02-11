import os
base = r'c:\Users\User\Desktop\NTU_WH\bridge\lib\models'
os.makedirs(base, exist_ok=True)
dart = "class Foo { final String x = 'hello'; }"
path = os.path.join(base, 'test_out.dart')
open(path, 'w').write(dart)
print('wrote', path)
