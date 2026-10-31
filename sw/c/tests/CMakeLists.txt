# Peripheral tests. periph_test runs on the board; periph_test_sim relies on
# the Verilator loopbacks and halts the simulator when done.
add_executable(periph_test periph_test/main.c)
target_link_libraries(periph_test common)

add_executable(periph_test_sim periph_test/main.c)
target_link_libraries(periph_test_sim common)
target_compile_definitions(periph_test_sim PRIVATE PERIPH_TEST_SIM)
