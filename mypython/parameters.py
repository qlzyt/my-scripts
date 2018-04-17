#位置参数，默认参数，可变参数，关键字参数，命名关键字参数

#位置参数
def PositionParameter(x, n):
    s=x**n
    return s

#错误的默认参数
def DefaultParameter(L=[]):
    L.append('end')
    return L

#默认参数
def DefaultParameter2(L=None):
    if L is None:
        L=[]
    L.append('end')
    return L

#可变参数，传入的是一个tuple
def ChangeableParameter(*num):
    s = 0
    for n in num:
        s = s + n*n
    return s

#关键字参数,传入的是一个dict
def KeywordsParameter(name, age,**kw):
    print(name,age,kw)


#命名关键字参数，限制传入的参数名称
#方法1 关键字参数前面有可变参数
def KeywordsParameter2(name, age, *args, job):
    print(name,age,job)
#方法2 关键字参数前面有*
def KeywordsParameter3(name, age, *, job):
    print(name,age,job)

#参数组合
def f1(a, b, c=0, *args, **kw):
    print('a =', a, 'b =', b, 'c =', c, 'args =', args, 'kw =', kw)

if __name__ == "__main__":
    # L = [1,2,3,4]
    # print(PositionParameter(2,3))
    # print(DefaultParameter2())
    # print(ChangeableParameter(1,2,3))
    # KeywordsParameter('zk','12',job='IT')
    # KeywordsParameter('zk', '12')
    KeywordsParameter2('zk', '12', job='IT')
    KeywordsParameter3('zk', '12', job='IT')




