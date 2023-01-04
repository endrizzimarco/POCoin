import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import Antd from 'ant-design-vue';
import 'ant-design-vue/dist/antd.css';
import './assets/main.css'

const app = createApp(App)

app.use(createPinia()).use(Antd);

app.mount('#app')
