import operator
def mylowwer(mylist):
    lowwerlist = [ i.lower() for i in mylist]
    return lowwerlist

def checkio(text):
    L = list(text)
    list2 = mylowwer(L)
    list3 = list(filter(lambda kk: kk.isalpha(), list2))
    mysetL = set(list3)
    L2 = []
    for item in mysetL:
        L2.append([item, list3.count(item)])
    a = sorted(L2, key=operator.itemgetter(1, 0))
    return max(a,key=lambda x:x[1])[0]



if __name__ == '__main__':
    #These "asserts" using only for self-checking and not necessary for auto-testing
    assert checkio("Hello World!") == "l", "Hello test"
    assert checkio("How do you do?") == "o", "O is most wanted"
    assert checkio("One") == "e", "All letter only once."
    assert checkio("Oops!") == "o", "Don't forget about lower case."
    assert checkio("AAaooo!!!!") == "a", "Only letters."
    assert checkio("abe") == "a", "The First."
    print("Start the long test")
    assert checkio("a" * 9000 + "b" * 1000) == "a", "Long."
    print("The local tests are done.")
    pass