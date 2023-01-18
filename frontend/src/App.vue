<script setup>
import Header from '@/components/layout/PageHeader.vue'
import NodeView from '@/components/layout/NodeView.vue'
import BlockchainView from '@/components/layout/BlockchainView.vue'
import WalletView from '@/components/layout/WalletView.vue'
</script>

<template lang="pug">
a-layout-header.flex.px-4.h-12.sticky.top-0.z-50.border-b.border-b-slate-800.header
  Header
a-layout
  a-layout-content.p-5
    a-row
      a-col(:span='8')
        WalletView
      a-col(:span='8')
        BlockchainView
      a-col(:span='8')
        NodeView
</template>

<style scoped>
.header {
  background: linear-gradient(to right, #000000, #141414);
  background-size: 400% 400%;

  -webkit-animation: header-animation 6s ease-in-out infinite;
  -moz-animation: header-animation 6s ease-in-out infinite;
  animation: header-animation 6s ease-in-out infinite;
}

@-webkit-keyframes header-animation {
  0% {
    background-position: 0% 50%;
  }
  50% {
    background-position: 100% 51%;
  }
  100% {
    background-position: 0% 50%;
  }
}
@-moz-keyframes header-animation {
  0% {
    background-position: 0% 50%;
  }
  50% {
    background-position: 100% 51%;
  }
  100% {
    background-position: 0% 50%;
  }
}
@-o-keyframes header-animation {
  0% {
    background-position: 0% 50%;
  }
  50% {
    background-position: 100% 51%;
  }
  100% {
    background-position: 0% 50%;
  }
}
@keyframes header-animation {
  0% {
    background-position: 0% 50%;
  }
  50% {
    background-position: 100% 51%;
  }
  100% {
    background-position: 0% 50%;
  }
}
</style>
