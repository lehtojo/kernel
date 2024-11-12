#include <thread>
#include <iostream>
#include <vector>

int fibonacci(int n)
{
	if (n < 2)
		return n;
	return fibonacci(n - 1) + fibonacci(n - 2);
}

void compute_fibonaccis(std::vector<int>& fibonaccis)
{
	std::cout << "Worker: Hello!" << std::endl;

	for (int i = 0; i < fibonaccis.capacity(); i++)
	{
		fibonaccis.push_back(fibonacci(i));
	}

	std::cout << "Worker: Goodbye!" << std::endl;
}

int main()
{
	std::vector<int> fibonaccis;
	fibonaccis.reserve(30);

	std::cout << "Starting the worker..." << std::endl;
	auto worker = std::thread([&]() { compute_fibonaccis(fibonaccis); });
	std::cout << "Waiting for the worker..." << std::endl;
	worker.join();

	std::cout << "Outputting results..." << std::endl;

	for (int fibonacci : fibonaccis)
	{
		std::cout << fibonacci << ' ';
	}

	std::cout << std::endl;

	std::cout << "Done." << std::endl;
	return 0;
}